#!/bin/bash
docker-compose down -v
docker-compose build oracle-base
docker-compose build oracle-installed
docker-compose up -d oracle-primary oracle-standby
docker logs -f oracle-primary
