"""Testinfra tests for the docker role."""

import testinfra


def test_docker_ce_installed(host):
    """Verify Docker CE packages are installed."""
    packages = [
        "docker-ce",
        "docker-ce-cli",
        "containerd.io",
        "docker-buildx-plugin",
        "docker-compose-plugin",
    ]
    for pkg in packages:
        assert host.package(pkg).is_installed, f"Package {pkg} is not installed"


def test_docker_service_enabled(host):
    """Verify Docker service is enabled."""
    svc = host.service("docker")
    assert svc.is_enabled


def test_docker_service_running(host):
    """Verify Docker service is running."""
    svc = host.service("docker")
    assert svc.is_running


def test_docker_command(host):
    """Verify docker CLI works."""
    cmd = host.run("docker --version")
    assert cmd.rc == 0


def test_docker_compose_command(host):
    """Verify docker compose plugin works."""
    cmd = host.run("docker compose version")
    assert cmd.rc == 0


def test_daemon_json_exists(host):
    """Verify daemon.json is deployed."""
    f = host.file("/etc/docker/daemon.json")
    assert f.exists
    assert f.mode == 0o644


def test_daemon_json_security_settings(host):
    """Verify daemon.json contains security hardening."""
    f = host.file("/etc/docker/daemon.json")
    assert f.contains('"live-restore": true')
    assert f.contains('"icc": false')
    assert f.contains('"no-new-privileges": true')
    assert '"experimental"' not in f.content_string


def test_daemon_json_logging(host):
    """Verify daemon.json configures log rotation."""
    f = host.file("/etc/docker/daemon.json")
    assert f.contains('"log-driver": "json-file"')
    assert f.contains('"max-size"')
    assert f.contains('"max-file"')


def test_docker_compose_directory(host):
    """Verify Docker Compose working directory exists."""
    d = host.file("/opt/docker-compose")
    assert d.exists
    assert d.is_directory
    assert d.mode == 0o755


def test_docker_config_directory(host):
    """Verify Docker config directory exists."""
    d = host.file("/etc/docker")
    assert d.exists
    assert d.is_directory
