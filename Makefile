.PHONY: build up down restart logs shell check-vpn check-ip clean help

help:
	@echo "Seedbox Docker - Available Commands"
	@echo "===================================="
	@echo "make build       - Build the Docker image"
	@echo "make up          - Start the container"
	@echo "make down        - Stop the container"
	@echo "make restart     - Restart the container"
	@echo "make logs        - View container logs"
	@echo "make shell       - Open shell in container"
	@echo "make check-vpn   - Check VPN connection status"
	@echo "make check-ip    - Check current IP address"
	@echo "make clean       - Remove container and image"

build:
	docker-compose build

up:
	docker-compose up -d
	@echo "Container started! Access Flood UI at http://localhost:5000"

down:
	docker-compose down

restart:
	docker-compose restart

logs:
	docker-compose logs -f

shell:
	docker exec -it seedbox /bin/bash

check-vpn:
	@echo "WireGuard Status:"
	@docker exec seedbox wg show 2>/dev/null || echo "WireGuard is not running or not configured"

check-ip:
	@echo "Current IP Address:"
	@docker exec seedbox curl ipinfo.io
	@echo ""

clean:
	docker-compose down
	docker rmi seedbox:latest
	@echo "Container and image removed"
