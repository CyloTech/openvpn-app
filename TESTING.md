# Testing Framework for OpenVPN Appbox App

Complete all applicable tests before submitting changes for review.

---

## Prerequisites

- Docker installed and running
- `Dockerfile`, `entrypoint.sh`, `moduser.sh`, `appbox.yml` in the repo

---

## 1. Build

```bash
docker build -t openvpn-app .
```

**Checklist:**

- [ ] Build completes without errors
- [ ] `bash`, `curl`, and `gosu` are installed
- [ ] `entrypoint.sh` is set as `ENTRYPOINT`
- [ ] `CMD` is set to supervisord

---

## 2. Fresh Install

```bash
docker volume create openvpn-configs
docker volume create openvpn-data

docker run --rm --cap-add=NET_ADMIN \
  -e OPENVPN_USER=admin \
  -e OPENVPN_PASSWORD='TestPass123!' \
  -e DOMAIN=localhost \
  -e EXTERNAL_PORT=1194 \
  -e INSTANCE_ID=test-fresh \
  -e SKIP_APPBOX_CALLBACK=1 \
  -v openvpn-configs:/configs \
  -v openvpn-data:/etc/openvpn \
  -p 8080:80 \
  -p 1194:1194/udp \
  openvpn-app
```

**Checklist:**

- [ ] Container starts without errors
- [ ] PKI is initialized (certificates generated)
- [ ] Default VPN client `config.ovpn` is created in `/configs`
- [ ] `.htpasswd` is created with the provided OPENVPN_USER
- [ ] `/etc/app_configured` is created
- [ ] Web interface is accessible at `http://localhost:8080`
- [ ] Basic auth works with the provided credentials
- [ ] `.ovpn` file can be downloaded
- [ ] After `/scripts/adduser.sh alice <password>`, alice can download `alice.ovpn` but gets 404 for `config.ovpn` and other users' profiles
- [ ] The install user gets 404 for other users' profiles

---

## 3. Restart

```bash
docker run -d --name openvpn-test --cap-add=NET_ADMIN \
  -e OPENVPN_USER=admin \
  -e OPENVPN_PASSWORD='TestPass123!' \
  -e DOMAIN=localhost \
  -e EXTERNAL_PORT=1194 \
  -e INSTANCE_ID=test-restart \
  -e SKIP_APPBOX_CALLBACK=1 \
  -v openvpn-configs:/configs \
  -v openvpn-data:/etc/openvpn \
  -p 8080:80 \
  -p 1194:1194/udp \
  openvpn-app

docker restart openvpn-test
```

**Checklist:**

- [ ] Container restarts without errors
- [ ] Entrypoint skips callback (app_configured exists)
- [ ] No duplicate PKI initialization
- [ ] VPN configs and credentials still work
- [ ] Web interface accessible

---

## 4. Upgrade

```bash
docker stop openvpn-test && docker rm openvpn-test
docker build -t openvpn-app .

docker run --rm --cap-add=NET_ADMIN \
  -e OPENVPN_USER=admin \
  -e OPENVPN_PASSWORD='TestPass123!' \
  -e DOMAIN=localhost \
  -e EXTERNAL_PORT=1194 \
  -e INSTANCE_ID=test-upgrade \
  -e SKIP_APPBOX_CALLBACK=1 \
  -v openvpn-configs:/configs \
  -v openvpn-data:/etc/openvpn \
  -p 8080:80 \
  -p 1194:1194/udp \
  openvpn-app
```

**Checklist:**

- [ ] Container starts without errors
- [ ] PKI initialization is skipped (configs exist)
- [ ] Existing .ovpn files are preserved
- [ ] TLS key comparison runs and regenerates certs if needed
- [ ] Callback is attempted
- [ ] Login still works with original credentials

---

## 5. Process Verification

```bash
docker exec openvpn-test ps aux
```

**Checklist:**

- [ ] supervisord is PID 1
- [ ] OpenVPN process is running
- [ ] nginx process is running

---

## 6. Signal Handling

```bash
time docker stop openvpn-test
```

**Checklist:**

- [ ] Container stops within 10 seconds
- [ ] No data corruption after stop

---

## 7. Password Change Script (moduser.sh)

```bash
docker exec openvpn-test /moduser.sh "NewPassword456!"
echo $?
```

**Checklist:**

- [ ] `/moduser.sh` exists and is executable
- [ ] Accepts one argument (new password)
- [ ] Updates the default user's password in `.htpasswd`
- [ ] Regenerates the .ovpn file for that user
- [ ] New password works for web interface login
- [ ] Prints usage and exits non-zero with no arguments

---

## 8. Persistence Verification

**Checklist:**

- [ ] VPN certificates persist across container replacement
- [ ] `.ovpn` files persist
- [ ] `.htpasswd` credentials persist
- [ ] OpenVPN server config persists

---

## 9. appbox.yml Validation

**Checklist:**

- [ ] `cap_add: NET_ADMIN` is set (required for VPN)
- [ ] UDP port 1194 is defined in `ports.udp.range`
- [ ] Both volumes (`/configs` and `/etc/openvpn`) are defined
- [ ] `behavior.expect_callback` is true
- [ ] Custom fields have appropriate validation

---

## Quick Reference

```bash
# Build
docker build -t openvpn-app .

# Fresh install
docker volume create openvpn-configs
docker volume create openvpn-data
docker run -d --name openvpn-test --cap-add=NET_ADMIN \
  -e OPENVPN_USER=admin -e OPENVPN_PASSWORD='TestPass123!' \
  -e DOMAIN=localhost -e EXTERNAL_PORT=1194 \
  -e INSTANCE_ID=test -e SKIP_APPBOX_CALLBACK=1 \
  -v openvpn-configs:/configs -v openvpn-data:/etc/openvpn \
  -p 8080:80 -p 1194:1194/udp openvpn-app

# Logs
docker logs -f openvpn-test

# Restart test
docker restart openvpn-test

# Password change test
docker exec openvpn-test /moduser.sh "NewPassword456!"

# Shell into container
docker exec -it openvpn-test bash

# Cleanup
docker stop openvpn-test && docker rm openvpn-test
docker volume rm openvpn-configs openvpn-data
```
