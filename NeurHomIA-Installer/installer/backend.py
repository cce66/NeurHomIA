from flask import Flask, jsonify, request
import subprocess, os, datetime, re

app = Flask(__name__)

SCRIPT_MANAGER = "/opt/neurhomia/installer/script_manager.sh"
SERVICE_MANAGER = "/opt/neurhomia/installer/service_manager.sh"
ENV_FILE = "/opt/neurhomia/.env"
LOG_FILE = "/opt/neurhomia/installer/install.log"

# =========================
# UTIL
# =========================

def safe(name):
    return re.match(r'^[a-zA-Z0-9_.-]+$', name)

def run(cmd):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    with open(LOG_FILE, "a") as f:
        f.write(f"\n=== {datetime.datetime.now()} ===\n{r.stdout}{r.stderr}\n")
    return r.stdout + r.stderr

def run_script(name, arg=""):
    return run(f"bash {SCRIPT_MANAGER} run_script {name} {arg}")

# =========================
# CONFIG ENV
# =========================

@app.route("/config/env", methods=["POST"])
def env():
    data = request.json
    with open(ENV_FILE, "w") as f:
        for k,v in data.items():
            f.write(f"{k}={v}\n")
    return jsonify({"status":"ok"})

# =========================
# INSTALL
# =========================

@app.route("/install/<name>", methods=["POST"])
def install(name):
    mapping = {
        "docker":"install_docker.sh",
        "ufw":"setup_ufw.sh",
        "fail2ban":"install_fail2ban.sh",
        "neurhomia":"deploy_neurhomia.sh",
        "mosquitto":"deploy_mosquitto.sh"
    }
    if name in mapping:
        return jsonify({"output": run_script(mapping[name])})
    return jsonify({"error":"unknown"})

@app.route("/install/mcp", methods=["POST"])
def mcp():
    profiles = request.json.get("profiles",[])
    out=""
    for p in profiles:
        out += run_script("deploy_mcp.sh", p)
    return jsonify({"output":out})

# =========================
# FULL INSTALL
# =========================

@app.route("/install/full", methods=["POST"])
def full():
    steps = [
        "install_docker.sh",
        "setup_ufw.sh",
        "install_fail2ban.sh",
        "deploy_mosquitto.sh",
        "deploy_neurhomia.sh"
    ]
    out=""
    for s in steps:
        out += run_script(s)
    return jsonify({"output":out})

# =========================
# DOCKER CONTROL
# =========================

@app.route("/docker/<action>/<name>", methods=["POST"])
def docker(action,name):
    if not safe(name): return jsonify({"error":"bad name"})
    return jsonify({"output": run(f"docker {action} {name}")})

# =========================
# UPDATE STACK
# =========================

@app.route("/update/<path:name>", methods=["POST"])
def update(name):
    return jsonify({"output": run_script("update_stack.sh", name)})

# =========================
# AUTO RESTART
# =========================

@app.route("/autorestart", methods=["POST"])
def autorestart():
    data = request.json
    service = data["name"]
    path = data["path"]
    return jsonify({"output": run(f"bash {SERVICE_MANAGER} {service} {path}")})

# =========================
# STATUS
# =========================

@app.route("/services")
def services():
    r = subprocess.run("docker ps -a --format '{{.Names}}|{{.Status}}'", shell=True, capture_output=True, text=True)
    res=[]
    for l in r.stdout.splitlines():
        if "|" in l:
            n,s = l.split("|",1)
            res.append({"name":n,"status":s})
    return jsonify(res)

@app.route("/installed")
def installed():
    base="/opt/neurhomia"
    found=[]
    for root,dirs,files in os.walk(base):
        if "docker-compose.yml" in files:
            found.append(root)
    return jsonify(found)

@app.route("/logs")
def logs():
    if os.path.exists(LOG_FILE):
        return open(LOG_FILE).read()
    return "no logs"

# =========================
app.run(host="0.0.0.0", port=8081)
