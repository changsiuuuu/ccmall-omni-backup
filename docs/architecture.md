# ccmall 시스템 아키텍처

## 프로젝트 개요

온프렘 DB를 메인으로 운영하고 클라우드에 예비 DB를 두는 하이브리드 구조입니다.
온프렘 DB 장애 시 예비 DB를 자동 승격시켜 최단 시간 내 서비스를 복구하는 것이 목표입니다.

---

## 전체 구조도

```
                        [사용자]
                           │
                      [Cloudflare]
                      DNS / HTTPS
                           │
                      [EC2-1 Web]  ← Public 서브넷
                       Nginx (HTTPS, Let's Encrypt)
                       FastAPI + Jinja2
                           │
                           │ DB 연결
                           │ (.env의 DB_HOST 동적 변경)
                           │
              ┌────────────┼────────────┬─────────────┐
           [정상]       [장애 발생]  [복구 중]      [복구 완료]
              │            │            │               │
              ▼            ▼            ▼               ▼
        [rocky01]     [EC2-2 Rec]  [EC2-3 신규]    [EC2-3 메인]
        온프렘 메인 DB  예비 DB     자동 프로비저닝   복구된 메인 DB
        PostgreSQL    Warm Standby  (Terraform)    PostgreSQL
             ▲            ▲             ▲
             │            │             │
             │   주기적    │             │ 백업 복원
             │   동기화    │             │
             └────────────┤             │                               
                          │             │
                          ▼             │
                        [S3 백업]────────┘
                       매일 전체 백업
                       콜드 데이터 (3개월+)

                          
```
📊 모니터링: Prometheus + Grafana
🔐 네트워크: Tailscale VPN (온프렘 ↔ EC2)
🔒 IaC 상태: S3 (tfstate) + DynamoDB (lock)
```

---

### 1. 사용자 트래픽 경로

- 사용자 → Cloudflare DNS → EC2-Web
- HTTPS 인증서: Let's Encrypt
- 도메인: everton.cloud

### 2. AWS 인프라

| 컴포넌트 | 역할 | 위치 |
|---------|------|------|
| EC2-Web | Nginx + FastAPI | Public Subnet |
| EC2-Rec | 예비 DB + 모니터링 + Tailscale 라우터 | Private Subnet |
| EC2-3 | 장애 복구용 신규 DB (동적 생성) | Private Subnet |
| EC2-NAT | Private 인스턴스의 인터넷 게이트웨이 | Public Subnet |
| S3 Bucket | DB 백업 저장소 | - |

### 3. 온프렘

- **rocky01** (172.16.8.201): 메인 PostgreSQL 서버, mgmt 역할
- Tailscale 통해 AWS와 연결


### 4. VPN (Tailscale)

- 온프렘 ↔ AWS 안전한 연결
- ccmall-Rec이 AWS 측 subnet router
- rocky01이 온프렘 측 subnet router
- 양쪽이 서로의 사설 IP 대역을 라우팅

### 5. CI/CD (GitHub Actions)

```
개발자 push
    ↓
GitHub Actions runner (Ubuntu)
    ↓
Terraform: AWS 리소스 생성/변경
    ↓
Ansible: 서버 구성 (Nginx, FastAPI, PostgreSQL 등)
```

### 6. 모니터링 (EC2-Rec)

- **Prometheus**: 메트릭 수집 (15초 간격)
- **Grafana**: 대시보드 시각화
- **Alertmanager**: 알림 (텔레그램 봇)
- **node_exporter**: 모든 서버에 설치
- **postgres_exporter**: DB 서버에 설치

### 7. 백업 시스템

#### 정기 백업
- **매일 00:00**: rocky01에서 전체 백업 → S3 업로드
- **1시간 마다**: 핵심 테이블 → EC2-Rec 동기화 (Warm Standby)

#### 백업 대상
- 데이터: customers, inventorys, orders, admins 테이블
- 콜드 데이터: 3개월 이상 된 주문/리뷰/로그 → S3 이관

## 재해 복구 시나리오

### 정상 상태
```
사용자 → EC2-Web → rocky01 (메인 DB)
              └→ EC2-Rec (Warm Standby, 핵심 데이터만)
```

### 장애 발생
```
1. rocky01 다운
2. Prometheus → Alertmanager → 텔레그램 알림
3. mgmt에서 Ansible 실행:
   - EC2-Web의 .env DB_HOST 변경 (→ EC2-Rec)
   - ccmall 서비스 재시작
4. 사용자 트래픽이 EC2-Rec으로 전환
```

### 백그라운드 복구
```
1. Terraform으로 EC2-3 신규 프로비저닝
2. S3 최신 백업 → EC2-3 복원
3. mgmt에서 Ansible 실행:
   - EC2-Web의 .env DB_HOST 변경 (→ EC2-3)
   - ccmall 서비스 재시작
4. EC2-3가 새 메인 DB로 동작
5. EC2-Rec은 다시 예비 상태로 복귀
```



---

## CI/CD 흐름

```
개발자
git push origin master
        │
        ▼
GitHub Actions (ubuntu 임시 서버)
        │
        ├─ 1. AWS 인증 (Secrets)
        │
        ├─ 2. 코드 체크아웃
        │
        ├─ 3. Terraform apply
        │      └─ EC2-Web, EC2-Rec 생성
        │      └─ inventory.yml, ansible.cfg 자동 생성
        │      └─ 60초 대기 (EC2 부팅)
        │
        ├─ 4. SSH 키 설정
        │      └─ Secrets에서 꺼내서 ~/.ssh/ansiblekey.pem 저장
        │
        ├─ 5. Ansible 실행
        │      ├─ ec2_bootstrap.yml  (user1 생성)
        │      ├─ setting/main.yml   (nginx, FastAPI 설치)
        │      └─ monitoring/playbook.yml (Prometheus, Grafana)
        │
        ├─ 6. Tailscale 설치
        │      └─ EC2-Web, EC2-Rec Tailscale 네트워크 등록
        │
        └─ 완료 ✅ (ubuntu 임시 서버 사라짐)



---
## 기술 스택

| 분류 | 기술 |
|------|------|
| IaC | Terraform |
| 구성 관리 | Ansible |
| CI/CD | GitHub Actions |
| 클라우드 | AWS (EC2, S3, VPC, IAM) |
| VPN | Tailscale |
| OS | Amazon Linux 2023, Rocky Linux 9 |
| 웹 서버 | Nginx |
| 백엔드 | Python, FastAPI |
| DB | PostgreSQL 15 |
| HTTPS | Let's Encrypt (certbot) |
| 모니터링 | Prometheus, Grafana, Alertmanager |
| 알림 | Telegram Bot |
| 백업 | pg_dump + AWS S3 |
| 스케줄러 | APScheduler |

---

## 폴더 구조

```
ccmall-omni-backup/
├── app/
│   ├── api/
│   ├── core/
│   ├── models/
│   ├── schemas/
│   └── tasks/
├── infra/
│   ├── deployment/
│   │   ├── ansible/
│   │   └── terraform/
│   ├── backup/
│   ├── monitoring/
│   └── recovery/
├── docs/
├── .github/
├── static/
└── requirements.txt
```