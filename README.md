# Moonlight Web - Streaming Automation with Robot Framework in Docker

Continuous streaming traffic generation and testing automation using **Robot Framework** with **SeleniumLibrary**, executed inside **Docker** containers. The script automates connecting to **Moonlight Web**, logging in, launching a game session (e.g., Xonotic), starting a match (Instant Action), sending periodic player inputs, and monitoring real-time network latency (Round Trip Time - RTT).

---

## 📁 Project Structure

```text
.
├── scripts/
│   ├── streaming_infinito.robot    # Full continuous loop automation on Moonlight Web
│   └── streaming.robot             # Standalone alternative script for direct video testing
├── resultados/                     # Host directory mounted to collect reports and latency metrics
├── .gitignore                      # Ignores runtime artifacts, temporary profiles, and reports
└── README.md                       # Project documentation
```

---

## 🚀 How to Run the Container

### Prerequisites
- [Docker](https://docs.docker.com/engine/install/) installed on your Linux system.

### 1. Create the results directory (if it does not exist yet)
From the project root:
```bash
mkdir -p resultados
```

### 2. Run the Docker container
Execute the following command in your terminal from the project root directory:

```bash
docker run --shm-size=2g --memory=4g --cpus=2 -d --name moonlight-docker \
  --restart unless-stopped \
  --network host \
  -e HOME=/tmp \
  -v $(pwd)/resultados:/opt/robotframework/reports:Z \
  -v $(pwd)/scripts:/opt/robotframework/tests:Z \
  --entrypoint robot \
  ppodgorsek/robot-framework:latest \
  --outputdir /opt/robotframework/reports /opt/robotframework/tests/streaming_infinito.robot
```

### Parameter Breakdown:
- `--name moonlight-docker`: Names the container.
- `--shm-size=2g`: Essential shared memory size to prevent Chrome renderer crashes during video/WebRTC streaming in Docker.
- `--memory=4g` / `--cpus=2`: Allocates sufficient system resources for 1080p @ 60 FPS streaming.
- `--network host`: Grants direct network connectivity to local LAN IP addresses (Moonlight server).
- `-v $(pwd)/resultados:...`: Mounts the host directory for reports, screenshots, and latency logs persistence.
- `-v $(pwd)/scripts:...`: Mounts your `.robot` test scripts inside the container.
- `--entrypoint robot`: Directly invokes Robot Framework CLI with the specified arguments.

---

## 📊 Monitoring and Checking Metrics

### Follow container logs in real time
```bash
docker logs -f moonlight-docker
```

### View network latency in real time
The network round trip time metric (**streamer to browser rtt**) is dynamically updated in `resultados/latency.txt`. To watch it live:
```bash
watch -n 1 "cat resultados/latency.txt"
```

### Stop and remove the container
```bash
docker stop moonlight-docker && docker rm moonlight-docker
```

---

## ⚙️ Configuration Variables

You can customize the test parameters in `scripts/streaming_infinito.robot` or pass them dynamically at runtime via Docker using `--variable`:

- `${URL_STREAMING}`: Moonlight Web endpoint (e.g., `https://<YOUR_SERVER_IP>:8081/`).
- `${MOONLIGHT_USER}` and `${MOONLIGHT_PASS}`: Login credentials.
- `${TEMPO_VIDEO}`: Duration of each streaming iteration in seconds (default: 250s).
- `${TILE_HOST}`: Target host identifier registered in Moonlight.

> [!TIP]
> **Security Best Practice:** Avoid committing plain-text passwords or internal infrastructure IPs to public Git repositories. You can pass them securely as environment variables or Robot Framework CLI variables without editing the script:
> ```bash
> docker run ... \
>   ppodgorsek/robot-framework:latest \
>   --variable URL_STREAMING:https://<YOUR_IP>:8081/ \
>   --variable MOONLIGHT_USER:<USERNAME> \
>   --variable MOONLIGHT_PASS:<PASSWORD> \
>   --outputdir /opt/robotframework/reports /opt/robotframework/tests/streaming_infinito.robot
> ```
