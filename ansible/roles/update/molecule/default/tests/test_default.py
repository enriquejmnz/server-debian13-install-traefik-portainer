"""Testinfra tests for the update role.

Note: The update role requires a running Traefik/Portainer stack.
In Docker-in-Docker environments, container operations may not work.
These tests verify the role's prerequisites and file state.
"""

import testinfra


def test_docker_compose_file_exists(host):
    """Verify docker-compose.yml exists (prerequisite for update)."""
    f = host.file("/opt/traefik-portainer/docker-compose.yml")
    assert f.exists


def test_docker_available(host):
    """Verify Docker CLI is available (prerequisite for update)."""
    cmd = host.run("docker --version")
    assert cmd.rc == 0


def test_docker_compose_available(host):
    """Verify docker compose plugin is available."""
    cmd = host.run("docker compose version")
    assert cmd.rc == 0


def test_install_dir_exists(host):
    """Verify install directory exists."""
    d = host.file("/opt/traefik-portainer")
    assert d.exists
    assert d.is_directory
