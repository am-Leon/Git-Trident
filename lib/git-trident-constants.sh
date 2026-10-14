#!/bin/bash
# =============================================================================
# Git Trident — Centralized Framework Constants
# =============================================================================

# Core Versioning (Single Source of Truth)
export TRIDENT_VERSION="0.2.0"

# Distribution and Repository Configuration
export GITHUB_REPO="am-Leon/Git-Trident"
export GITHUB_RELEASE_API="https://api.github.com/repos/$GITHUB_REPO/releases/latest"

# File & Path Configurations
# Configuration schema version.
#
# Bumped when keys are renamed, removed, or change meaning. `config validate`
# reports a config older than this, so a stale file is a visible warning rather
# than a silent misconfiguration.
export CONFIG_SCHEMA_CURRENT="1"

export CONFIG_FILE_NAME="git-trident-config"
export GLOBAL_CONFIG_FILE_NAME=".git-trident-config"
export PROJECT_DIR_NAME=".git-trident"
