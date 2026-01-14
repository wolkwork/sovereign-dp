# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

sovereign-dp (Data Platform as a Service) is building a local data lakehouse platform with:
- **Kubernetes** (minikube/kind/k3s) for container orchestration
- **rustfs** for S3-compatible object storage
- **Trino** as the distributed SQL query engine
- **Nessie** as the Iceberg catalog server
- **Apache Iceberg** table format for lakehouse functionality

The project is in active development, building infrastructure and foundational services.

## Environment Configuration

The project uses environment variables defined in `.env`:
- `ANTHROPIC_BASE_URL`: Points to a Pydantic gateway proxy for Anthropic API
- `ANTHROPIC_AUTH_TOKEN`: Authentication token for the gateway

These credentials should be loaded before running any Anthropic API integrations.

## Task Tracking with Beads

**IMPORTANT**: This project uses **beads** (`bd` command) for issue tracking. DO NOT use the TodoWrite tool.

### Working with Beads

```bash
# View all issues
bd list

# Find unblocked work ready to start
bd ready

# Show issue details
bd show <issue-id>

# Update issue status
bd update <issue-id> --status in_progress
bd update <issue-id> --status done
bd close <issue-id>  # Mark as done

# Create new issues
bd create "Task description" --type task --priority 2

# Sync with git (run when committing)
bd sync
```

### Workflow

1. Start work: `bd list` or `bd ready` to see available tasks
2. Update status: `bd update <id> --status in_progress` when starting
3. Complete work: `bd close <id>` when finished
4. Commit and sync: Always run `bd sync` before/with git commits

### Before Closing Issues

Before marking a task as done, ensure documentation is updated:
- Update README.md if the task adds/changes user-facing features, commands, or workflows
- Update scripts/README.md if the task modifies deployment scripts
- Keep documentation in sync with actual implementation

For more details, see AGENTS.md or run `bd prime`.

## Project Structure

The repository is set up with:
- Terraform-compatible .gitignore (suggesting infrastructure-as-code will be used)
- Git version control initialized
- Logging directory structure in `logs/`

## Development Notes

### Current Phase: Infrastructure Setup

Building a local lakehouse development environment. Key components:
- **K8s Cluster**: Local cluster (minikube/kind/k3s) for all services
- **Object Storage**: rustfs as S3-compatible storage with sovereign-dp bucket
- **Query Engine**: Trino for distributed SQL queries
- **Catalog**: Nessie for Iceberg table versioning
- **Table Format**: Apache Iceberg for ACID transactions

### Infrastructure Approach

- Kubernetes manifests and Helm charts for deployment
- Terraform for infrastructure-as-code (based on .gitignore)
- Local-first development, cloud-portable architecture
- Configuration through environment variables and K8s secrets
