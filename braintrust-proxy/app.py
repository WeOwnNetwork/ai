"""
Braintrust Proxy for AnythingLLM + OpenRouter
Captures all LLM calls and logs to Braintrust for observability.
"""
import os
import json
import time
from flask import Flask, request, Response, jsonify
from openai import OpenAI
import braintrust
from braintrust import current_span, init_logger, start_span, traced

app = Flask(__name__)

# Initialize Braintrust logger
logger = init_logger(
    project=os.getenv("BRAINTRUST_PROJECT_NAME", "AnythingLLM"),
    api_key=os.getenv("BRAINTRUST_API_KEY"),
)

# Configure OpenRouter client
openrouter = OpenAI(
    api_key=os.getenv("OPENROUTER_API_KEY"),
    base_url="https://openrouter.ai/api/v1",
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


@traced(type="llm", name="Chat Completion", notrace_io=True)
def traced_chat_completion(messages, model, **kwargs):
    """Execute chat completion with Braintrust tracing."""
    start_time = time.time()
    
    response = openrouter.chat.completions.create(
        model=model,
        messages=messages,
        **kwargs
    )
    
    duration_ms = (time.time() - start_time) * 1000
    
    # Log to Braintrust
    content = response.choices[0].message.content if response.choices else ""
    usage = response.usage
    
    current_span().log(
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
        },
    )
    
    return response


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
        
        with start_span(name="AnythingLLM Request"):
            response = traced_chat_completion(messages, model, **kwargs)
            braintrust.flush()  # Ensure logs are sent
            return jsonify(response.model_dump())
            
    except Exception as e:
        return jsonify({"error": {"message": str(e), "type": "proxy_error"}}), 500


def stream_chat_completion(messages, model, **kwargs):
    """Handle streaming chat completions."""
    def generate():
        full_content = ""
        start_time = time.time()
        
        with start_span(name="Streaming Chat Completion") as span:
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
                
                # Log complete interaction
                span.log(
                    input=messages,
                    output=full_content,
                    metrics={"duration_ms": (time.time() - start_time) * 1000},
                    metadata={"model": model, "stream": True, **kwargs},
                )
                braintrust.flush()  # Ensure logs are sent
            except Exception as e:
                yield f"data: {json.dumps({'error': str(e)})}\n\n"
    
    return Response(generate(), mimetype="text/event-stream")


@traced(type="embedding", name="Embeddings", notrace_io=True)
def traced_embeddings(input_text, model):
    """Execute embeddings with Braintrust tracing."""
    start_time = time.time()
    
    response = openrouter.embeddings.create(
        model=model,
        input=input_text,
    )
    
    duration_ms = (time.time() - start_time) * 1000
    
    current_span().log(
        input=input_text if isinstance(input_text, str) else f"[{len(input_text)} texts]",
        output=f"[{len(response.data)} embeddings]",
        metrics={
            "total_tokens": response.usage.total_tokens if response.usage else 0,
            "duration_ms": duration_ms,
        },
        metadata={"model": model, "provider": "openrouter"},
    )
    
    return response


@app.route("/v1/embeddings", methods=["POST"])
def embeddings():
    """Proxy embeddings with Braintrust tracing."""
    try:
        data = request.json
        input_text = data.get("input", "")
        model = data.get("model", "text-embedding-ada-002")
        
        with start_span(name="Embeddings Request"):
            response = traced_embeddings(input_text, model)
            return jsonify(response.model_dump())
            
    except Exception as e:
        return jsonify({"error": {"message": str(e), "type": "proxy_error"}}), 500


if __name__ == "__main__":
    port = int(os.getenv("PORT", 8080))
    print(f"🧠 Braintrust Proxy running on port {port}")
    print(f"📊 Logging to Braintrust project: {os.getenv('BRAINTRUST_PROJECT_NAME', 'AnythingLLM')}")
    app.run(host="0.0.0.0", port=port, debug=False)
