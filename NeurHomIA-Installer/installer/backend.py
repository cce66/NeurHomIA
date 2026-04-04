from flask import Flask, jsonify, request
import subprocess, os, datetime, re

app = Flask(__name__)

BASE_DIR = "/opt/neurhomia"
INSTALLER_DIR = f"{BASE_DIR}/installer"
SCRIPT_MANAGER = f"{INSTALLER_DIR}/script_manager.sh"
SERVICE_MANAGER = f"{INSTALLER_DIR}/service_manager.sh"
ENV_FILE = f"{BASE_DIR}/.env"
LOG_FILE = f"{INSTALLER_DIR}/install.log"

# =========================
# UTIL
# =========================

def safe(name):
    return re.match(r'^[a-zA-Z0-9_.\\/-]+$', name)

def run(cmd):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

    log_entry = f"\n=== {datetime.datetime.now()} ===\n{cmd}\n{result.stdout}{result.stderr}\n"
    with open(LOG_FILE, "a") as f:
        f.write(log_entry)

    return result.stdout + result.stderr

def run_script(script, arg=""):
    return run(f"bash {SCRIPT_MANAGER} run_script {script} {arg}")

def detect_path(name):
    if "mosquitto" in name:
        return f"{BASE_DIR}/mosquitto"
    if "neurhomia" in name:
        return f"{BASE_DIR}/app"
    return f"{BASE_DIR}/mcp/{name}"

# =========================
# CONFIG ENV
# =========================

@app.route("/config/env", methods=["POST"])
def config_env():
    data = request.json
    with open(ENV_FILE, "w") as f:
        for k, v in data.items():
            f.write(f"{k}={v}\n")
    return jsonify({"status": "ok"})

# =========================
# INSTALL
# =========================

@app.route("/install/<target>", methods=["POST"])
def install(target):
    mapping = {
        "docker": "install_docker.sh",
        "ufw": "setup_ufw.sh",
        "fail2ban": "install_fail2ban.sh",
        "mosquitto": "deploy_mosquitto.sh",
        "neurhomia": "deploy_neurhomia.sh"
    }

    if target not in mapping:
        return jsonify({"error": "unknown target"})

    return jsonify({"output": run_script(mapping[target])})

# =========================
# MCP
# =========================

@app.route("/mcp/list")
def mcp_list():
    base = f"{BASE_DIR}/mcp"
    if not os.path.exists(base):
        return jsonify([])
    return jsonify([d for d in os.listdir(base) if d.startswith("MCP-")])

@app.route("/install/mcp", methods=["POST"])
def install_mcp():
    profiles = request.json.get("profiles", [])
    output = ""

    for p in profiles:
        if safe(p):
            output += run_script("deploy_mcp.sh", p)

    return jsonify({"output": output})

# =========================
# FULL INSTALL
# =========================

@app.route("/install/full", methods=["POST"])
def install_full():
    steps = [
        "install_docker.sh",
        "setup_ufw.sh",
        "install_fail2ban.sh",
        "deploy_mosquitto.sh",
        "deploy_neurhomia.sh"
    ]

    output = ""
    for step in steps:
        output += f"\n=== {step} ===\n"
        output += run_script(step)

    return jsonify({"output": output})

# =========================
# DOCKER CONTROL
# =========================

@app.route("/docker/<action>/<name>", methods=["POST"])
def docker_control(action, name):
    if not safe(name):
        return jsonify({"error": "invalid name"})

    return jsonify({"output": run(f"docker {action} {name}")})

# =========================
# UPDATE STACK
# =========================

@app.route("/update/<name>", methods=["POST"])
def update(name):
    path = detect_path(name)
    return jsonify({"output": run_script("update_stack.sh", path)})

# =========================
# AUTO RESTART
# =========================

@app.route("/autorestart", methods=["POST"])
def autorestart():
    data = request.json
    name = data.get("name")
    path = data.get("path")

    if not safe(name):
        return jsonify({"error": "invalid name"})

    return jsonify({
        "output": run(f"bash {SERVICE_MANAGER} {name} {path}")
    })

# =========================
# STATUS
# =========================

@app.route("/services")
def services():
    result = subprocess.run(
        "docker ps -a --format '{{.Names}}|{{.Status}}'",
        shell=True,
        capture_output=True,
        text=True
    )

    services = []
    for line in result.stdout.splitlines():
        if "|" in line:
            name, status = line.split("|", 1)
            services.append({"name": name, "status": status})

    return jsonify(services)

@app.route("/installed")
def installed():
    found = []
    for root, dirs, files in os.walk(BASE_DIR):
        if "docker-compose.yml" in files:
            found.append(root)
    return jsonify(found)

@app.route("/logs")
def logs():
    if os.path.exists(LOG_FILE):
        with open(LOG_FILE) as f:
            return f.read()
    return "No logs"

# =========================

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8081)
