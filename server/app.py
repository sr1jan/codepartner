import os
from pathlib import Path
from flask import Flask, request, Response
import llm
from log_utils import setup_logger

app = Flask(__name__)

API_KEY = os.environ.get("CODEPARTNER_API_KEY")
if not API_KEY:
    raise ValueError("CODEPARTNER_API_KEY environment variable is not set")

model = llm.get_model("groq-openai-llama3")
model.key = API_KEY

conversations = {}


logger = setup_logger(
    Path(__file__).parent, "codepartner_server", max_size_mb=10, backup_count=5
)


@app.route("/explain", methods=["POST"])
def explain_text():
    data = request.json
    text = data.get("text", "")
    query = data.get("query", "")
    conversation_id = data.get("conversation_id")
    logger.info(f"[EXPLAIN] CONVERSATION_ID: {conversation_id}")
    logger.info(f"[EXPLAIN] QUERY: {query}")

    if conversation_id not in conversations:
        conversations[conversation_id] = model.conversation()
    conversation = conversations[conversation_id]

    if len(query) == 0:
        query = "Please explain the above content!"

    prompt = ""
    if len(text) > 0:
        prompt = f"{text}\n\n"
    prompt += query

    explanation_stream = conversation.prompt(prompt, stream=True)

    def generate():
        for chunk in explanation_stream:
            yield chunk

    return Response(generate(), content_type="text/plain")


if __name__ == "__main__":
    app.run(host="localhost", port=5000, debug=True)
