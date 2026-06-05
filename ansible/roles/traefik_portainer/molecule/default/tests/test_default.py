"""Testinfra tests for the traefik_portainer role.

Note: Container deployment (docker_compose_v2) may not work in
Docker-in-Docker environments. These tests focus on FILE CONFIGURATION:
directories, templates, and permissions.
"""

from pathlib import Path

import testinfra


def load_portainer_version():
    """Read the canonical Portainer version from the shared repo file."""
    version_file = Path(__file__).resolve().parents[5] / "inventory/group_vars/all/versions.env"
    for line in version_file.read_text(encoding="utf-8").splitlines():
        if line.startswith("PORTAINER_VERSION="):
            return line.split("=", 1)[1].strip()
    raise AssertionError("PORTAINER_VERSION not found in versions.env")


def load_traefik_version():
    """Read the canonical Traefik version from the shared repo file."""
    version_file = Path(__file__).resolve().parents[5] / "inventory/group_vars/all/versions.env"
    for line in version_file.read_text(encoding="utf-8").splitlines():
        if line.startswith("TRAEFIK_VERSION="):
            return line.split("=", 1)[1].strip()
    raise AssertionError("TRAEFIK_VERSION not found in versions.env")


def test_install_dir_exists(host):
    """Verify install directory exists with correct permissions."""
    d = host.file("/opt/traefik-portainer")
    assert d.exists
    assert d.is_directory
    assert d.mode == 0o750


def test_traefik_data_dirs(host):
    """Verify Traefik data directories are created."""
    dirs = [
        "/opt/traefik-portainer/traefik-data",
        "/opt/traefik-portainer/traefik-data/configurations",
        "/opt/traefik-portainer/portainer-data",
    ]
    for d in dirs:
        assert host.file(d).exists, f"Directory {d} does not exist"
        assert host.file(d).is_directory, f"{d} is not a directory"


def test_docker_compose_file(host):
    """Verify docker-compose.yml is deployed with correct images."""
    f = host.file("/opt/traefik-portainer/docker-compose.yml")
    assert f.exists
    assert f.contains(f"traefik:{load_traefik_version()}")
    assert f.contains(f"portainer/portainer-ce:{load_portainer_version()}")


def test_docker_compose_labels(host):
    """Verify docker-compose.yml contains Traefik routing labels."""
    f = host.file("/opt/traefik-portainer/docker-compose.yml")
    assert f.contains("traefik.enable=true")
    assert f.contains("traefik.docker.network=proxy")
    assert f.contains("traefik.http.routers.traefik-secure")
    assert f.contains("traefik.http.routers.portainer-secure")


def test_traefik_yml(host):
    """Verify traefik.yml static configuration is deployed."""
    f = host.file("/opt/traefik-portainer/traefik-data/traefik.yml")
    assert f.exists
    assert f.contains("api:")
    assert f.contains("dashboard: true")
    assert f.contains("httpChallenge")
    assert f.contains("certResolver: letsencrypt")


def test_traefik_yml_entrypoints(host):
    """Verify traefik.yml configures HTTP and HTTPS entrypoints."""
    f = host.file("/opt/traefik-portainer/traefik-data/traefik.yml")
    assert f.contains('address: ":80"')
    assert f.contains('address: ":443"')


def test_dynamic_yml(host):
    """Verify dynamic.yml is deployed with security headers and auth."""
    f = host.file("/opt/traefik-portainer/traefik-data/configurations/dynamic.yml")
    assert f.exists
    assert f.contains("secureHeaders")
    assert f.contains("user-auth")
    assert f.contains("tls:")


def test_dynamic_yml_permissions(host):
    """Verify dynamic.yml has restrictive permissions."""
    f = host.file("/opt/traefik-portainer/traefik-data/configurations/dynamic.yml")
    assert f.exists
    assert f.mode == 0o640


def test_dynamic_yml_security_headers(host):
    """Verify dynamic.yml includes security header middleware."""
    f = host.file("/opt/traefik-portainer/traefik-data/configurations/dynamic.yml")
    assert f.contains("stsSeconds: 31536000")
    assert f.contains("contentTypeNosniff: true")
    assert f.contains("customFrameOptionsValue: \"SAMEORIGIN\"")


def test_acme_json(host):
    """Verify acme.json exists with restrictive permissions."""
    f = host.file("/opt/traefik-portainer/traefik-data/acme.json")
    assert f.exists
    assert f.mode == 0o600


def test_apache2_utils_installed(host):
    """Verify apache2-utils (htpasswd) is installed."""
    assert host.package("apache2-utils").is_installed
