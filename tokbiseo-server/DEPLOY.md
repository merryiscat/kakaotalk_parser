# 톡비서 서버 — 미니 PC 배포 가이드

Ubuntu 24.04 (XCP-ng VM) + Docker 환경 기준

---

## 1단계: Docker 설치 (미니 PC에서)

```bash
# 필요한 패키지 설치
sudo apt update
sudo apt install -y ca-certificates curl

# Docker 공식 GPG 키 추가
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Docker 저장소 등록
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Docker 설치
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 현재 사용자를 docker 그룹에 추가 (sudo 없이 docker 사용 가능)
sudo usermod -aG docker $USER

# 그룹 변경 적용 (재로그인 대신)
newgrp docker

# 설치 확인
docker --version
docker compose version
```

---

## 2단계: 서버 코드 가져오기

### 방법 A: Git으로 클론 (추천)

```bash
# tokbiseo-server를 별도 Git 저장소로 관리하는 경우
git clone <저장소URL> ~/tokbiseo-server
cd ~/tokbiseo-server
```

### 방법 B: 파일 직접 복사 (scp)

```bash
# 개발 PC (Windows Git Bash)에서 실행
scp -r /c/Users/minhy/project/kakaotalk_parser/tokbiseo-server/ 사용자@미니PC_IP:~/tokbiseo-server/
```

---

## 3단계: 환경변수 설정

```bash
cd ~/tokbiseo-server

# 템플릿 복사
cp .env.example .env

# 편집 — 실제 API 키 입력
nano .env
```

`.env` 에 최소한 아래 내용을 채우세요:

```
OPENAI_API_KEY=sk-실제키값
TAVILY_API_KEY=tvly-실제키값
YOUTUBE_API_KEY=AIza실제키값
```

---

## 4단계: 서버 실행

```bash
cd ~/tokbiseo-server

# 이미지 빌드 + 백그라운드 실행
docker compose up -d --build

# 실행 상태 확인
docker compose ps

# 로그 확인 (Ctrl+C로 종료)
docker compose logs -f

# 서버 상태 테스트
curl http://localhost:3936/health
```

정상이면 `{"status":"ok"}` 응답이 옵니다.

---

## 5단계: 방화벽 설정

```bash
# UFW 방화벽에 포트 3936 허용
sudo ufw allow 3936/tcp
sudo ufw status
```

---

## 6단계: 톡비서 앱 연결

1. 미니 PC의 내부 IP 확인: `ip addr show` 또는 `hostname -I`
2. 톡비서 앱 → 설정 → 서버 URL에 입력:
   ```
   http://미니PC_IP:3936
   ```
3. 연결 테스트 버튼으로 확인

---

## 자주 쓰는 명령어

| 명령어 | 설명 |
|--------|------|
| `docker compose up -d` | 서버 시작 |
| `docker compose down` | 서버 중지 |
| `docker compose restart` | 서버 재시작 |
| `docker compose logs -f` | 실시간 로그 보기 |
| `docker compose up -d --build` | 코드 변경 후 재빌드 |
| `docker compose ps` | 컨테이너 상태 확인 |

---

## 외부 접속 (공유기 포트포워딩)

집 밖에서도 접속하려면:

1. 공유기 관리 페이지 접속 (보통 192.168.0.1)
2. 포트포워딩 설정:
   - 외부 포트: 3936
   - 내부 IP: 미니 PC IP
   - 내부 포트: 3936
   - 프로토콜: TCP
3. 톡비서 앱 서버 URL: `http://공인IP:3936`

---

## 문제 해결

### 컨테이너가 시작되지 않을 때
```bash
docker compose logs tokbiseo-server
```

### 이미지 재빌드가 필요할 때 (의존성 변경 등)
```bash
docker compose down
docker compose build --no-cache
docker compose up -d
```

### 디스크 공간 정리 (오래된 이미지 삭제)
```bash
docker system prune -f
```
