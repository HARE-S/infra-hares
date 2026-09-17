#!/usr/bin/env bash
set -e

docker compose --profile test up -d db-test
docker compose run --rm \
  -e APP_ENV=testing \
  -e TEST_DATABASE_URL=postgresql://test_user:test_password@db-test:5432/hares_test \
  backend pytest "$@"
