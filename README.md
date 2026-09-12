# Instant Lab

Instant Lab is a Docker-based cybersecurity practice environment for Raspberry Pi and Linux systems. It provides an interactive terminal dashboard for launching security tools, intentionally vulnerable web applications, and monitoring stacks.

Use this project only in an isolated lab or against systems you own or are explicitly authorized to test.

## Features

- Interactive launcher for all lab services
- Docker installation and daemon checks
- Port conflict checks before services start
- Parrot Security and Kali Linux containers
- Nuclei vulnerability scanner
- DVWA, OWASP Juice Shop, and bWAPP targets
- ELK and Wazuh monitoring stacks
- Wazuh agent deployment
- Container status and cleanup utilities

## Requirements

- Linux system, Raspberry Pi, or another linux compatible computer
- At least 4 GB RAM recommended for the ELK or Wazuh stacks

The security-tool containers may require additional CPU, memory, and disk space. Start only the services needed for your exercise.

## Quick Start

Clone the repository:

```bash
git clone https://github.com/swayan-basu/Instant_lab.git
cd Instant_lab
chmod +x start_main.sh
find scripts -type f -name '*.sh' -exec chmod +x {} +
./start_main.sh
```

On first launch, `start_main.sh`:

1. Checks whether Docker is installed and accessible.
2. Offers to run `scripts/setup/start_dock.sh` if Docker is missing.
3. Creates the shared `instant_lab_network` Docker network when needed.
4. Optionally displays the current container status.
5. Opens the interactive service menu

The menu stays open after a service starts. Choose `0` to exit the menu; running containers continue in the background.

### Wazuh Login

The current single-node configuration uses:

```text
Username: admin
Password: SecretPassword
```

The Wazuh dashboard uses a self-signed certificate, so a browser warning may appear on first access.
These credentials are intended for local lab use only. Change the password before allowing access from another network.

## Direct Launchers

Every service can be started without the dashboard. Run commands from the repository root:

```bash
bash scripts/scanners/start_parrot.sh
bash scripts/scanners/start_rkali.sh
bash scripts/scanners/start_nuclei.sh

bash scripts/targets/start_dvwa.sh
bash scripts/targets/start_juice.sh
bash scripts/targets/start_bwapp.sh

bash scripts/siem/start_elk.sh
bash scripts/siem/start_wazuh.sh
bash scripts/siem/start_wazuh_agent.sh
```

## Docker Network

The interactive dashboard creates a bridge network named:

```text
instant_lab_network
```

Inspect it with:

```bash
docker network inspect instant_lab_network
```

The root `docker-compose.yml` also defines a Compose network named `instant-lab-net`. These names are different. If a scanner cannot resolve a target by its container name, verify that both containers are attached to the same Docker network:

```bash
docker inspect CONTAINER_NAME
docker network connect instant_lab_network CONTAINER_NAME
```

Use the second command only when the target is not already attached to the required network.

## Container Management

List running containers:

```bash
docker ps
```

List all containers:

```bash
docker ps -a
```

View logs:

```bash
docker logs CONTAINER_NAME
docker logs -f CONTAINER_NAME
```

Stop or restart a container:

```bash
docker stop CONTAINER_NAME
docker start CONTAINER_NAME
```

The status utility can optionally stop and remove all containers:

```bash
bash scripts/setup/status.sh
```

Review the prompt carefully before confirming cleanup. To remove unused Docker resources, use:

```bash
docker system prune
```

## Docker Setup and Permissions

If Docker is not installed, run:

```bash
bash scripts/setup/start_dock.sh
```

The setup script installs Docker on Debian-based systems, starts the Docker service, and adds the current user to the `docker` group. Log out and back in, or run:

```bash
newgrp docker
```

Then verify access:

```bash
docker info
```

## Troubleshooting

### Docker daemon is not running

```bash
sudo systemctl start docker
sudo systemctl enable docker
docker info
```

### Permission denied when using Docker

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

### A port is already in use

Check the process using a port:

```bash
sudo ss -tulpn | grep ':8080'
```

Replace `8080` with the affected port. Stop the conflicting service before starting the lab service.

### A container exits or fails to start

```bash
docker ps -a
docker logs CONTAINER_NAME
df -h
free -h
```

For ELK and Wazuh, allow extra time for the indexer and dashboard to initialize. Wazuh also configures the host kernel setting `vm.max_map_count` for the indexer.

### Check script syntax

```bash
bash -n main.sh
find scripts -type f -name '*.sh' -exec bash -n {} +
```

If available, ShellCheck can provide additional static analysis:

```bash
shellcheck main.sh scripts/**/*.sh
```
> **Warning:** The `work/`, `msf/`, `wazuh/`, and `wazuh-agent/` directories may contain persistent data created by the lab services. Do not delete them unless you intend to remove that data.

## Security and Legal Notice

DVWA, Juice Shop, bWAPP, and the security-tool containers are intended for authorized training and testing. Keep the lab on a private network, do not expose vulnerable services to the public internet, and obtain permission before testing any system that you do not own.

## License

Project-owned code and documentation are licensed under the [Apache License
2.0](LICENSE). Third-party components retain their original licenses; see
[NOTICE](NOTICE) for the main third-party components used by this project.
