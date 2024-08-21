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


def get_explanation(text, conversation_id=None):
    if conversation_id not in conversations:
        conversations[conversation_id] = model.conversation()

    conversation = conversations[conversation_id]
    prompt = f"Please explain the following content:\n\n{text}"
    response = conversation.prompt(prompt, stream=True)
    return response


@app.route("/explain", methods=["POST"])
def explain_text():
    data = request.json
    text = data["text"]
    conversation_id = data.get("conversation_id")
    logger.info(f"[EXPLAIN] CONVERSATION_ID: {conversation_id}")

    explanation_stream = get_explanation(text, conversation_id)

    def generate():
        for chunk in explanation_stream:
            yield chunk

    return Response(generate(), content_type="text/plain")


@app.route("/follow_up", methods=["POST"])
def follow_up_query():
    data = request.json
    query = data["query"]
    conversation_id = data["conversation_id"]
    logger.info(f"[FOLLOW_UP] CONVERSATION_ID: {conversation_id}")

    if conversation_id not in conversations:
        return Response("Conversation not found", status=404)

    conversation = conversations[conversation_id]
    response = conversation.prompt(query, stream=True)

    def generate():
        for chunk in response:
            yield chunk

    return Response(generate(), content_type="text/plain")


if __name__ == "__main__":
    app.run(host="localhost", port=5000, debug=True)
