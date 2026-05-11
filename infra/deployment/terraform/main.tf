# infra/deployment/terraform/main.tf
# AWS에 Web, Rec 서버를 provisioning한다.

terraform {
  required_version = "~> 1.14.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# 1. provider 설정
provider "aws" {
  region = "ap-northeast-2" # 서울 리전
}

# 2. vpc 및 네트워크 생성
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "ccmall-vpc" }
}

# igw
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "ccmall-igw" }
}

# 현재 리전에서 사용 가능한 가용 영역 데이터를 가져온다.
data "aws_availability_zones" "available" {
  state = "available"
}

# public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "ccmall-public-subnet"
  }
}

# private subnet
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "ccmall-private-subnet"
  }
}

# public subnet 라우팅 테이블
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  # public subnet에서 인터넷으로 나가는 트래픽은 IGW로 보낸다.
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "ccmall-public-rt"
  }
}

# public subnet과 public route table 연결
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# NAT Gateway에 붙일 탄력적 IP 생성
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "ccmall-nat-eip"
  }
}

# NAT Gateway 생성
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "ccmall-nat-gw"
  }
}

# private subnet 라우팅 테이블
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  # private subnet에서 외부 인터넷으로 나가는 트래픽은 NAT Gateway로 보낸다.
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name = "ccmall-private-rt"
  }
}

# private subnet과 private route table 연결
resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# pem 파일 관련 작업
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# AWS Key Pair 등록
resource "aws_key_pair" "kp" {
  key_name   = "ccmall-key"
  public_key = tls_private_key.pk.public_key_openssh

  tags = {
    Name = "ccmall-key"
  }
}

# Terraform이 생성하는 초기 접속용 개인키
resource "local_file" "ssh_key" {
  filename        = local.ssh_key_file
  content         = tls_private_key.pk.private_key_pem
  file_permission = "0600"
}

# web 서버 보안 그룹
resource "aws_security_group" "sg_web" {
  name   = "SG-Web"
  vpc_id = aws_vpc.main.id

  # SSH
  # 실습 단계에서는 0.0.0.0/0으로 열고, 운영에서는 본인 공인 IP/32로 제한한다.
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Node Exporter
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound 전체 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SG-Web"
  }
}

# rec 서버 보안 그룹
resource "aws_security_group" "sg_rec" {
  name   = "SG-Rec"
  vpc_id = aws_vpc.main.id

  # EC2-Web에서 EC2-Rec으로 SSH 허용
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_web.id]
  }

  # EC2-Web에서 EC2-Rec PostgreSQL 접근 허용
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_web.id]
  }

  # mgmt 서버가 Tailscale 대역을 통해 EC2-Rec PostgreSQL에 접근
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["172.16.8.0/24"]
  }

  # mgmt Prometheus -> EC2-Rec Node Exporter
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["172.16.8.0/24"]
  }

  # mgmt Prometheus -> EC2-Rec PostgreSQL Exporter
  ingress {
    from_port   = 9187
    to_port     = 9187
    protocol    = "tcp"
    cidr_blocks = ["172.16.8.0/24"]
  }

  # outbound 전체 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SG-Rec"
  }
}

# s3 버킷 및 IAM 설정
resource "random_id" "bucket_suffix" {
  byte_length = 2
}

resource "aws_s3_bucket" "my_bucket" {
  bucket = "ccmall-bucket-${random_id.bucket_suffix.hex}"
}

# EC2가 S3에 접근할 IAM Role
resource "aws_iam_role" "ec2_s3_role" {
  name = "EC2-S3-ACCESS-ROLE"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_full_access" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "EC2-S3-Instance-Profile"
  role = aws_iam_role.ec2_s3_role.name
}

# Amazon Linux 2023 최신 AMI 검색
data "aws_ami" "latest_al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# web ec2 만들기
resource "aws_instance" "ec2_web" {
  ami                         = data.aws_ami.latest_al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  private_ip                  = "10.0.1.10"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.sg_web.id]
  key_name                    = aws_key_pair.kp.key_name

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # 서버 생성 시 hostname을 Web으로 변경한다.
  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname Web

    # /etc/hosts 에도 일관성 있게 반영
    grep -q "127.0.0.1 Web" /etc/hosts || echo "127.0.0.1 Web" >> /etc/hosts

    # user1 생성
    id user1 >/dev/null 2>&1 || useradd -m -s /bin/bash user1

    # wheel 그룹에 추가
    usermod -aG wheel user1

    # sudo NOPASSWD 설정
    echo "user1 ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/user1
    chmod 0440 /etc/sudoers.d/user1

    # SSH 공개키 등록
    mkdir -p /home/user1/.ssh
    echo "${file("/home/user1/.ssh/ansiblekey.pem.pub")}" > /home/user1/.ssh/authorized_keys
    chown -R user1:user1 /home/user1/.ssh
    chmod 700 /home/user1/.ssh
    chmod 600 /home/user1/.ssh/authorized_keys
  EOF

  tags = {
    Name = "ccmall-Web"
  }
}

# rec ec2 만들기
resource "aws_instance" "ec2_rec" {
  ami                         = data.aws_ami.latest_al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_subnet.id
  private_ip                  = "10.0.2.30"
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.sg_rec.id]
  key_name                    = aws_key_pair.kp.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # 서버 생성 시 hostname을 Rec으로 변경한다.
  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname Rec

    # /etc/hosts 에도 일관성 있게 반영
    grep -q "127.0.0.1 Rec" /etc/hosts || echo "127.0.0.1 Rec" >> /etc/hosts

    # user1 생성
    id user1 >/dev/null 2>&1 || useradd -m -s /bin/bash user1

    # wheel 그룹에 추가
    usermod -aG wheel user1

    # sudo NOPASSWD 설정
    echo "user1 ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/user1
    chmod 0440 /etc/sudoers.d/user1

    # SSH 공개키 등록
    mkdir -p /home/user1/.ssh
    echo "${file("/home/user1/.ssh/ansiblekey.pem.pub")}" > /home/user1/.ssh/authorized_keys
    chown -R user1:user1 /home/user1/.ssh
    chmod 700 /home/user1/.ssh
    chmod 600 /home/user1/.ssh/authorized_keys
  EOF
  tags = {
    Name = "ccmall-Rec"
  }
}

# 생성된 EC2-Web의 public ip를 출력
output "web_public_ip" {
  description = "EC2-Web의 public ipv4 주소"
  value       = aws_instance.ec2_web.public_ip
}

# 생성된 EC2-Web의 private ip를 출력
output "web_private_ip" {
  description = "EC2-Web의 private ipv4 주소"
  value       = aws_instance.ec2_web.private_ip
}

# 생성된 EC2-Rec의 private ip를 출력
output "rec_private_ip" {
  description = "EC2-Rec의 private ipv4 주소"
  value       = aws_instance.ec2_rec.private_ip
}

# 생성된 s3의 버킷 이름 출력
output "s3_bucket_name" {
  description = "생성된 s3 버킷의 이름"
  value       = aws_s3_bucket.my_bucket.id
}
locals {
  # 현재 Terraform 코드가 있는 위치
  # 예: /home/user/project/infra/deployment/terraform
  terraform_dir = abspath(path.module)

  # deployment 디렉터리
  # 예: /home/user/project/infra/deployment
  deployment_dir = dirname(local.terraform_dir)

  # infra 루트 디렉터리
  # 예: /home/user/project/infra
  infra_dir = dirname(local.deployment_dir)

  # 공용 ansible.cfg 위치
  ansible_cfg = "${local.infra_dir}/ansible.cfg"

  # 공용 inventory.yml 위치
  inventory_dir  = "${local.infra_dir}/inventory"
  inventory_file = "${local.inventory_dir}/inventory.yml"

  # roles 경로
  deployment_roles_dir = "${local.deployment_dir}/ansible/roles"
  monitoring_roles_dir = "${local.infra_dir}/monitoring/ansible/roles"
  backup_roles_dir     = "${local.infra_dir}/backup/ansible/roles"
  recovery_roles_dir   = "${local.infra_dir}/recovery/ansible/roles"

  # Terraform이 생성하는 초기 접속용 key
  ssh_key_file = "${local.terraform_dir}/ccmall-key.pem"

  # 부트스트랩 이후 운영 접속용 key
  ansible_key_file = "/home/user1/.ssh/ansiblekey.pem"

  # 부트스트랩 playbook 위치
  bootstrap_playbook = "${local.deployment_dir}/ansible/ec2_bootstrap.yml"
}
resource "terraform_data" "prepare_ansible_dirs" {
  triggers_replace = {
    inventory_dir = local.inventory_dir
  }

  provisioner "local-exec" {
    command = "mkdir -p ${local.inventory_dir}"
  }
}
# public ip와 private ip를 이용해서 infra/inventory/inventory.yml 파일 만들기
# inventory는 EC2-Web, EC2-Rec만 단순하게 정의한다.
# 접속 사용자와 key는 ansible.cfg 또는 실행 명령어에서 결정한다.
resource "local_file" "ansible_inventory" {
  filename = local.inventory_file

  depends_on = [
    terraform_data.prepare_ansible_dirs
  ]

  content = yamlencode({
    all = {
      hosts = {
        # EC2-Web은 public subnet에 있으므로 public ip로 직접 접속한다.
        "EC2-Web" = {
          ansible_host = aws_instance.ec2_web.public_ip
        }

        # EC2-Rec은 private subnet에 있으므로 EC2-Web을 통해 점프 접속한다.
        "EC2-Rec" = {
          ansible_host = aws_instance.ec2_rec.private_ip

          # %r은 현재 Ansible 접속 사용자로 치환된다.
          # 부트스트랩 때는 ec2-user,
          # 운영 때는 user1로 동작한다.
          ansible_ssh_common_args = "-o ProxyJump=%r@${aws_instance.ec2_web.public_ip} -o StrictHostKeyChecking=no"
        }

        # rocky01은 VMware에 있는 Rocky Linux 기반 On-Prem DB 서버다.
        # VPN, 라우팅 설정이 완료된 이후 mgmt 서버에서 172.16.8.201로 SSH 접속할 수 있어야 한다.
        # 환경상 지금은 같은 컴퓨터의 VMware에서 돌아가고 있지만, 다른 컴퓨터에서 돌아가고 있다고 가정한다.
        #
        # "onprem_db" = {
        #   ansible_host = "172.16.8.201"
        # }
      }
    }
  })
}

resource "local_file" "ansible_cfg" {
  filename = local.ansible_cfg

  content = <<-EOF
    [defaults]
    inventory = ${local.inventory_file}
    remote_user = user1
    private_key_file = ${local.ansible_key_file}
    host_key_checking = False
    remote_tmp = ~/.ansible/tmp
    roles_path = ${local.deployment_roles_dir}:${local.monitoring_roles_dir}:${local.backup_roles_dir}:${local.recovery_roles_dir}
    interpreter_python = auto_silent
  EOF
}

resource "terraform_data" "bootstrap_user1" {
  depends_on = [
    aws_instance.ec2_web,
    aws_instance.ec2_rec,
    local_file.ssh_key,
    local_file.ansible_inventory,
    local_file.ansible_cfg
  ]

  triggers_replace = {
    web_instance_id = aws_instance.ec2_web.id
    rec_instance_id = aws_instance.ec2_rec.id
  }

  provisioner "local-exec" {
    command = "sleep 60 && ANSIBLE_CONFIG=${local.ansible_cfg} ANSIBLE_SSH_PIPELINING=1 ansible-playbook -u ec2-user --private-key ${local.ssh_key_file} ${local.bootstrap_playbook}"
  }
}

# =============================================
# Terraform → Ansible 모니터링 자동실행
# EC2 생성 + inventory + ansible.cfg 준비 후 실행
# bootstrap_user1 완료 후 monitoring/playbook.yml 실행
# =============================================
resource "terraform_data" "run_monitoring_playbook" {

  depends_on = [
    aws_instance.ec2_web,          # Web 서버 생성 완료 후
    aws_instance.ec2_rec,          # Rec 서버 생성 완료 후
    local_file.ansible_inventory,  # inventory.yml 생성 완료 후
    local_file.ansible_cfg,        # ansible.cfg 생성 완료 후
    terraform_data.bootstrap_user1 # bootstrap 완료 후
  ]

  triggers_replace = {
    web_instance_id = aws_instance.ec2_web.id
    rec_instance_id = aws_instance.ec2_rec.id
    bootstrap_id    = terraform_data.bootstrap_user1.id
  }

  provisioner "local-exec" {
    # ansible.cfg 가 있는 infra/ 폴더에서 실행
    working_dir = local.infra_dir

    command = <<-EOT
      echo "======================================"
      echo " EC2 SSH 준비 대기 중... (60초)"
      echo "======================================"
      sleep 60

      echo "======================================"
      echo " Ansible 모니터링 Playbook 시작!"
      echo "======================================"
      ANSIBLE_CONFIG=${local.ansible_cfg} \
      ANSIBLE_SSH_PIPELINING=1 \
      ansible-playbook monitoring/playbook.yml

      echo "======================================"
      echo " Playbook 완료!"
      echo "======================================"
    EOT
  }
}