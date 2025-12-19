"""
Braintrust Proxy for AnythingLLM + OpenRouter
Captures all LLM calls and logs to Braintrust for observability.
"""
import os
import json
import time
import sys
from flask import Flask, request, Response, jsonify
from openai import OpenAI
import braintrust

app = Flask(__name__)

# Configure OpenRouter client
openrouter = OpenAI(
    api_key=os.getenv("OPENROUTER_API_KEY"),
    base_url="https://openrouter.ai/api/v1",
)

def get_logger():
    """Get or create Braintrust logger (handles gunicorn worker forks)."""
    return braintrust.init_logger(
        project=os.getenv("BRAINTRUST_PROJECT_NAME", "AnythingLLM"),
        api_key=os.getenv("BRAINTRUST_API_KEY"),
    )


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint."""
    return jsonify({"status": "ok", "service": "braintrust-proxy"})


@app.route("/v1/models", methods=["GET"])
def list_models():
    """Proxy models list from OpenRouter."""
    try:
        models = openrouter.models.list()
        return jsonify(models.model_dump())
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/v1/chat/completions", methods=["POST"])
def chat_completions():
    """Proxy chat completions with Braintrust tracing."""
    try:
        data = request.json
        messages = data.get("messages", [])
        model = data.get("model", "openai/gpt-3.5-turbo")
        stream = data.get("stream", False)
        
        # Extract optional parameters
        kwargs = {}
        for key in ["temperature", "max_tokens", "top_p", "frequency_penalty", "presence_penalty", "stop"]:
            if key in data:
                kwargs[key] = data[key]
        
        if stream:
            return stream_chat_completion(messages, model, **kwargs)
        
        # Non-streaming request
        start_time = time.time()
        
        response = openrouter.chat.completions.create(
            model=model,
            messages=messages,
            **kwargs
        )
        
        duration_ms = (time.time() - start_time) * 1000
        content = response.choices[0].message.content if response.choices else ""
        usage = response.usage
        
        # Log to Braintrust
        try:
            logger = get_logger()
            logger.log(
                input=messages,
                output=content,
                metrics={
                    "prompt_tokens": usage.prompt_tokens if usage else 0,
                    "completion_tokens": usage.completion_tokens if usage else 0,
                    "total_tokens": usage.total_tokens if usage else 0,
                    "duration_ms": duration_ms,
                },
                metadata={
                    "model": model,
                    "temperature": kwargs.get("temperature"),
                    "max_tokens": kwargs.get("max_tokens"),
                    "provider": "openrouter",
                    "stream": False,
                },
            )
            braintrust.flush()
            print(f"[Braintrust] Logged chat completion: {model}", file=sys.stderr)
        except Exception as log_err:
            print(f"[Braintrust] Log error: {log_err}", file=sys.stderr)
        
        return jsonify(response.model_dump())
            
    except Exception as e:
        print(f"[Proxy] Error: {e}", file=sys.stderr)
        return jsonify({"error": {"message": str(e), "type": "proxy_error"}}), 500


def stream_chat_completion(messages, model, **kwargs):
    """Handle streaming chat completions."""
    def generate():
        full_content = ""
        start_time = time.time()
        
        try:
            stream = openrouter.chat.completions.create(
                model=model,
                messages=messages,
                stream=True,
                **kwargs
            )
            
            for chunk in stream:
                if chunk.choices and chunk.choices[0].delta.content:
                    full_content += chunk.choices[0].delta.content
                yield f"data: {json.dumps(chunk.model_dump())}\n\n"
            
            yield "data: [DONE]\n\n"
            
            # Log to Braintrust after streaming completes
            try:
                duration_ms = (time.time() - start_time) * 1000
                logger = get_logger()
                logger.log(
                    input=messages,
                    output=full_content,
                    metrics={"duration_ms": duration_ms},
                    metadata={"model": model, "stream": True, "provider": "openrouter", **kwargs},
                )
                braintrust.flush()
                print(f"[Braintrust] Logged streaming completion: {model}", file=sys.stderr)
            except Exception as log_err:
                print(f"[Braintrust] Stream log error: {log_err}", file=sys.stderr)
        except Exception as e:
            print(f"[Proxy] Stream error: {e}", file=sys.stderr)
            yield f"data: {json.dumps({'error': str(e)})}\n\n"
    
    return Response(generate(), mimetype="text/event-stream")


@app.route("/v1/embeddings", methods=["POST"])
def embeddings():
    """Proxy embeddings with Braintrust tracing."""
    try:
        data = request.json
        input_text = data.get("input", "")
        model = data.get("model", "text-embedding-ada-002")
        
        start_time = time.time()
        response = openrouter.embeddings.create(model=model, input=input_text)
        duration_ms = (time.time() - start_time) * 1000
        
        # Log to Braintrust
        try:
            logger = get_logger()
            logger.log(
                input=input_text if isinstance(input_text, str) else f"[{len(input_text)} texts]",
                output=f"[{len(response.data)} embeddings]",
                metrics={
                    "total_tokens": response.usage.total_tokens if response.usage else 0,
                    "duration_ms": duration_ms,
                },
                metadata={"model": model, "provider": "openrouter", "type": "embedding"},
            )
            braintrust.flush()
            print(f"[Braintrust] Logged embeddings: {model}", file=sys.stderr)
        except Exception as log_err:
            print(f"[Braintrust] Embeddings log error: {log_err}", file=sys.stderr)
        
        return jsonify(response.model_dump())
            
    except Exception as e:
        print(f"[Proxy] Embeddings error: {e}", file=sys.stderr)
        return jsonify({"error": {"message": str(e), "type": "proxy_error"}}), 500


if __name__ == "__main__":
    port = int(os.getenv("PORT", 8080))
    print(f"🧠 Braintrust Proxy running on port {port}")
    print(f"📊 Logging to Braintrust project: {os.getenv('BRAINTRUST_PROJECT_NAME', 'AnythingLLM')}")
    app.run(host="0.0.0.0", port=port, debug=False)
