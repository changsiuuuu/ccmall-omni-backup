# 📦 CCmall: Omni-Backup
> **IaC 기반의 하이브리드 클라우드 데이터 자동 백업 및 복구 시스템 구축**
**Team 💬Cloud-Crew Tem**
> 
## 🛠 1. Tech Stack & Infrastructure
- **Language**: Python 3.11.7
- **Backend**: FastAPI 0.109.0
- **Database**: PostgreSQL 15 (Docker)
- **IaC & Automation**: Terraform 1.5.7 / Ansible 2.15.0
- **Cloud / Virtual**: AWS / VMware (Hybrid Environment)
- **Observability**: Prometheus / Grafana / Slack Alert 연동
- **CI/CD**: GitHub Actions (Docker Build & Push)
- 
## 프로젝트 소개
- 서비스명: CCmall (물류 기반 이커머스 서비스)
- 프로젝트 목표: 장애 상황에서도 서비스가 유지될 수 있는 자동 백업/복구 체계 구축
- 핵심 기술: AWS, VMware, Terraform, Ansible, FastAPI, PostgreSQL, Docker, Prometheus, Grafana, GitHub Actions
- 
## 📁 2. Directory Structure
코드와 인프라 자산의 효율적 관리를 위해 아래와 같은 표준 구조를 준수합니다.

```text
project/
├── app/                        # FastAPI 애플리케이션 (백엔드 로직)
│   ├── api/                    # API 엔드포인트 (customers, inventory, orders)
│   ├── core/                   # 시스템 설정 및 환경 변수 관리
│   ├── crud/                   # Database CRUD 로직
│   ├── models/                 # DB 테이블 스키마 정의
│   ├── schemas/                # 데이터 검증 및 직렬화 (Pydantic)
│   ├── services/               # 외부 서비스 연동 (S3, 메시지 전송 등)
│   ├── tasks/                  # 백업 스케줄러 (APScheduler)
│   └── main.py                 # 애플리케이션 엔트리포인트
├── infra/                      # 인프라 및 운영 레이어
│   ├── terraform/              # IaC 기반 AWS 리소스 관리
│   ├── ansible/                # OS 설정 및 패키지 배포 자동화
│   ├── monitoring/             # Prometheus, Grafana 관찰 체계
│   └── automation/             # 장애 대응(Failover) 및 복구 스크립트
├── cicd/                       # GitHub Actions 파이프라인 설정
├── docker/                     # 컨테이너 빌드 및 오케스트레이션 설정
├── docs/                       # 기술 설계서 및 아키텍처 다이어그램
└── requirements.txt            # 파이썬 의존성 패키지 명세

```

- ## 📅3. 프로젝트 진행 방식 (Operational Process)
우리 팀은 효율적인 개발과 완벽한 결과물 도출을 위해 아래와 같은 프로세스를 준수합니다.

### 1단계: 마일스톤 및 데일리 스케줄링
- **주차별 목표 수립**: Notion 로드맵을 기반으로 해당 주차의 핵심 마일스톤을 확정합니다.
- **데일리 업무 배정**: 스크럼을 통해 '오늘의 할 일'을 정의하고 담당자를 배정합니다.

### 2단계: 로컬 우선 개발 및 검증 (Local-First)
- **환경 일관성**: 모든 팀원은 확정된 Python 가상환경 및 Docker 컨테이너에서 개발을 시작합니다.
- **사전 검증**: 본인의 로컬 환경 또는 개인 AWS/VM 환경에서 기능 구현 및 단위 테스트를 완료합니다.

### 3단계: 실시간 이슈 공유 및 문서화
- **Fail-Fast**: 기술적 장애나 병목 현상 발생 시, 즉시 메신저를 통해 팀원과 공유하여 해결책을 모색합니다.
- **결과 자산화**: 구현된 기능과 트러블슈팅 내역은 마지막에 반드시 기술 문서로 남깁니다.

### 4단계: 데일리 싱크 및 회고 (Daily Wrap-up)
- **마지막 1시간의 법칙**: 매일 업무 종료 1시간 전 아래 작업을 수행합니다.
  - **공유**: 오늘 진행된 작업 내용 및 코드 리뷰 브리핑
  - **기록**: Notion 회의록 및 작업 로그 업데이트
  - **준비**: 익일 우선순위 업무 선정 및 역할 분담
## 🤝 4. 팀 협업 및 코드 관리 규칙 (Collaboration & Git Rules)

성공적인 GitOps 운영과 코드 품질 유지를 위해 팀 전체가 준수해야 할 필수 가이드라인입니다.

### 🌿 5. 브랜치 전략 (Branch Strategy)
모든 팀원은 작업 성격에 맞는 브랜치를 생성하여 작업하며, `master` 브랜치는 배포 전용으로 관리합니다.

- **`master`**: 최종 통합 및 프로덕션 배포 브랜치 (팀장 전용 관리)
- **`feature/기능명`**: 새로운 기능 개발 및 로직 구현
- **`fix/버그명`**: 긴급 버그 수정 및 코드 오류 해결
- **`docs/문서명`**: README, 계획서, 설계서 등 문서 작업
- **`refactor/대상`**: 코드 구조 개선 및 최적화 (기능 변화 없음)

### 🚀 6. 협업 및 PR 규칙 (Pull Request Policy)
- **master 브랜치 보호**: `master` 브랜치에 직접 푸시(Direct Push)는 절대 금지합니다.
- **PR 필수 기입 항목**: 모든 PR은 아래 내용을 포함하여 작성해야 합니다.
   **작업 내용**: 어떤 기능을 구현했는지 상세히 설명
   **관련 이슈**: 연관된 작업이나 트래블슈팅 히스토리 언급
   **리뷰 및 병합**: 팀장의 코드 리뷰 및 최종 승인(Approve) 후 머지를 진행합니다.

### 💬 6.1 커밋 메시지 컨벤션 (Commit Convention)
일관된 프로젝트 이력 관리를 위해 `type: 설명` 형식을 준수합니다.

| Type | 설명 | 예시 |
| :--- | :--- | :--- |
| **feat** | 새로운 기능 구현 | `feat: 재고관리 API 구현` |
| **fix** | 버그 및 오류 수정 | `fix: DB 연결 오류 수정` |
| **docs** | 문서 업데이트 및 수정 | `docs: README 업데이트` |
| **test** | 테스트 코드 추가 및 검증 | `test: 백업 스크립트 테스트 추가` |
| **chore** | 환경 설정 및 라이브러리 관리 | `chore: 환경설정 파일 정리` |
| **refactor** | 코드 리팩토링 | `refactor: S3 이관 로직 구조 개선` |

### 📂 6.2 문서 및 자산 관리 (Documentation)
프로젝트와 관련된 모든 지식 자산은 아래의 채널을 통해 동기화합니다.

- **계획서 및 회의록**: [Notion] 실시간 일정 관리 및 데일리 스크럼 기록
- **코드 및 인프라 설정**: [GitHub] 버전 관리 및 코드 리뷰 수행
- **기술 문서**: [docs 폴더] 아키텍처 다이어그램, 배포 가이드, 모니터링 명세서 보관
