from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/")
def home():
    response = jsonify({
        "message": "Backend B is running"
    })
    response.headers["X-Backend"] = "B"
    return response


@app.route("/api/status")
def status():
    response = jsonify({
        "backend": "B",
        "status": "ok"
    })
    response.headers["X-Backend"] = "B"
    return response


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3002)
