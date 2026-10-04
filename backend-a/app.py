from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/")
def home():
    response = jsonify({
        "message": "Backend A is running"
    })
    response.headers["X-Backend"] = "A"
    return response


@app.route("/api/status")
def status():
    response = jsonify({
        "backend": "A",
        "status": "ok"
    })
    response.headers["X-Backend"] = "A"
    return response


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3001)
