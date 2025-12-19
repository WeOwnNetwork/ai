# OpenRouter Model Guide for AnythingLLM

A reference guide for configuring LLM models via the Braintrust proxy with OpenRouter.

## Quick Reference: Frontier Models (December 2025)

| Model | OpenRouter ID | Context Window | Max Output | Recommended Max Tokens |
|-------|---------------|----------------|------------|------------------------|
| **Claude Sonnet 4.5** | `anthropic/claude-sonnet-4.5` | 200K | 16K | `8192` |
| **Claude Opus 4.5** | `anthropic/claude-opus-4.5` | 200K | 16K | `8192` |
| **Gemini 3 Pro** | `google/gemini-3-pro-preview` | 1M | 64K | `16384` |
| **Gemini 3 Flash** | `google/gemini-3-flash-preview` | 1M | 64K | `8192` |
| **GPT-5** | `openai/gpt-5` | 128K | 32K | `8192` |
| **GPT-5 Thinking** | `openai/gpt-5-thinking` | 128K | 100K | `16384` |
| **o3** | `openai/o3` | 200K | 100K | `16384` |
| **o4-mini** | `openai/o4-mini` | 200K | 100K | `8192` |
| **DeepSeek V3** | `deepseek/deepseek-chat` | 64K | 8K | `4096` |
| **Llama 3.3 70B** | `meta-llama/llama-3.3-70b-instruct` | 128K | 4K | `4096` |

## How to Find Model IDs on OpenRouter

1. Go to [openrouter.ai/models](https://openrouter.ai/models)
2. Search or filter for your desired model
3. Click on the model to view its page
4. The **model ID** is in the URL and on the page (e.g., `anthropic/claude-sonnet-4.5`)

**Format**: `provider/model-name` (e.g., `anthropic/claude-sonnet-4.5`, `openai/gpt-5`)

## AnythingLLM Configuration

### Settings Location
`Settings → AI Providers → LLM → Generic OpenAI`

### Fields to Configure

| Field | What to Enter |
|-------|---------------|
| **Base URL** | `http://braintrust-proxy.braintrust.svc.cluster.local:8080/v1` |
| **API Key** | `dummy` (any value - proxy handles auth) |
| **Chat Model Name** | OpenRouter model ID (e.g., `anthropic/claude-sonnet-4.5`) |
| **Token context window** | Model's context window (see table above) |
| **Max Tokens** | Your preferred output limit (see recommendations) |

## Understanding Tokens

### What is a Token?
A token ≈ ~4 characters or ~¾ of a word in English.

| Text | Approximate Tokens |
|------|-------------------|
| "Hello" | 1 token |
| "Hello, how are you today?" | ~6 tokens |
| 1 page of text | ~400-500 tokens |
| A typical email | ~200-300 tokens |

### Context Window vs Max Tokens

| Term | Definition | Direction |
|------|-----------|-----------|
| **Context Window** | Total capacity for conversation (input + output) | Both ways |
| **Max Tokens** | Limit on model's response length | Output only |

```
Context Window = Your Prompt (input) + Model's Response (output)
                                        ↑
                                   Max Tokens limits this
```

## Choosing Max Tokens

### By Use Case

| Use Case | Recommended Max Tokens |
|----------|------------------------|
| Quick Q&A, chat | `1024` - `2048` |
| Detailed explanations | `4096` |
| Code generation | `8192` |
| Long-form content | `8192` - `16384` |
| Maximum possible | Model's limit |

### Trade-offs

| Higher Max Tokens | Lower Max Tokens |
|-------------------|------------------|
| ✅ Longer responses possible | ✅ Faster responses |
| ✅ Better for code/documents | ✅ Lower cost |
| ❌ Higher latency | ❌ May truncate long answers |
| ❌ Higher cost per request | |

**Recommendation**: Start with `4096` for general use, increase if responses get cut off.

## Finding a Model's Context Window

### Method 1: OpenRouter Model Page (Recommended)
1. Go to [openrouter.ai/models](https://openrouter.ai/models)
2. Click on your model (e.g., Claude Sonnet 4.5)
3. Look for **Context Length** in the model specs
4. This is your **Token context window** value

### Method 2: Provider Documentation
| Provider | Documentation |
|----------|--------------|
| Anthropic | [docs.anthropic.com/models](https://docs.anthropic.com/en/docs/about-claude/models) |
| OpenAI | [platform.openai.com/docs/models](https://platform.openai.com/docs/models) |
| Google | [ai.google.dev/gemini-api/docs](https://ai.google.dev/gemini-api/docs) |

### Method 3: API Response
When you make a request, the response headers or error messages often include context limits.

### Quick Reference
| Model Family | Typical Context Window |
|--------------|----------------------|
| Claude 4.5 | 200,000 |
| Gemini 3 | 1,000,000 |
| GPT-5 | 128,000 |
| o3/o4 | 200,000 |
| DeepSeek | 64,000 |
| Llama 3.3 | 128,000 |

## Model Recommendations by Task

### Coding & Software Development
| Task | Best Model | Why |
|------|-----------|-----|
| Complex refactoring | `anthropic/claude-opus-4.5` | Best reasoning for large codebases |
| Daily coding | `anthropic/claude-sonnet-4.5` | Excellent balance of speed/quality |
| Quick fixes | `openai/gpt-5` | Fast, good for simple tasks |

### Research & Analysis
| Task | Best Model | Why |
|------|-----------|-----|
| Long documents | `google/gemini-3-pro-preview` | 1M context window |
| Deep reasoning | `openai/o3` | Extended thinking capabilities |
| Quick summaries | `anthropic/claude-sonnet-4.5` | Fast, accurate |

### General Chat
| Task | Best Model | Why |
|------|-----------|-----|
| Everyday questions | `anthropic/claude-sonnet-4.5` | Great all-rounder |
| Cost-sensitive | `deepseek/deepseek-chat` | Excellent value |
| Speed priority | `google/gemini-3-flash-preview` | Fastest response |

## Switching Models

Just change the **Chat Model Name** field in AnythingLLM to any OpenRouter model ID. No proxy changes needed.

**Example**: To switch from Claude to GPT-5:
- Change `anthropic/claude-sonnet-4.5` → `openai/gpt-5`
- Update **Token context window** to `128000`
- Optionally adjust **Max Tokens**

## Model Details

### Claude 4.5 Family (Anthropic)

**Claude Sonnet 4.5** - `anthropic/claude-sonnet-4.5`
- Best for: Coding, agents, general tasks
- Context: 200K tokens (1M with beta header via direct API)
- Max output: 16K tokens (128K with beta)
- Strengths: Excellent code generation, tool use, extended autonomous operation

**Claude Opus 4.5** - `anthropic/claude-opus-4.5`
- Best for: Complex reasoning, difficult problems
- Context: 200K tokens
- Max output: 16K tokens
- Strengths: Frontier reasoning, handles ambiguity well, multi-system debugging

### Gemini 3 Family (Google)

**Gemini 3 Pro** - `google/gemini-3-pro-preview`
- Best for: Long documents, multimodal tasks
- Context: **1M tokens** (largest available)
- Max output: 64K tokens
- Strengths: Massive context, image/video/audio understanding

**Gemini 3 Flash** - `google/gemini-3-flash-preview`
- Best for: Speed-sensitive tasks
- Context: 1M tokens
- Max output: 64K tokens
- Strengths: Pro-level intelligence at Flash speed/pricing

### GPT-5 Family (OpenAI)

**GPT-5** - `openai/gpt-5`
- Best for: General tasks, fast responses
- Context: 128K tokens
- Max output: 32K tokens
- Strengths: Well-rounded, reliable

**GPT-5 Thinking** - `openai/gpt-5-thinking`
- Best for: Complex reasoning tasks
- Context: 128K tokens
- Max output: 100K tokens
- Strengths: Extended thinking for difficult problems

### Reasoning Models (OpenAI)

**o3** - `openai/o3`
- Best for: Math, science, complex reasoning
- Context: 200K tokens
- Max output: 100K tokens
- Note: Slower, higher cost, exceptional for hard problems

**o4-mini** - `openai/o4-mini`
- Best for: Reasoning at lower cost
- Context: 200K tokens
- Max output: 100K tokens
- Note: Good balance of reasoning capability and speed

### Budget Options

**DeepSeek V3** - `deepseek/deepseek-chat`
- Best for: Cost-effective general use
- Context: 64K tokens
- Max output: 8K tokens
- Strengths: Excellent price/performance ratio

**Llama 3.3 70B** - `meta-llama/llama-3.3-70b-instruct`
- Best for: Open-source preference
- Context: 128K tokens
- Max output: 4K tokens
- Strengths: Good quality, no vendor lock-in

## Troubleshooting

### "Model not found" error
- Check the model ID is exactly correct (case-sensitive)
- Verify the model is available on OpenRouter
- Some models may be in preview or require special access

### Responses getting cut off
- Increase **Max Tokens** setting
- Check you haven't exceeded context window with your prompt

### Slow responses
- Try a faster model (Flash variants, GPT-5)
- Reduce **Max Tokens** if you don't need long responses
- Consider that reasoning models (o3, GPT-5 Thinking) are intentionally slower

## Resources

- [OpenRouter Models](https://openrouter.ai/models) - Browse all available models
- [OpenRouter Docs](https://openrouter.ai/docs) - API documentation
- [Braintrust Dashboard](https://www.braintrust.dev/app/projects) - View your traces

---

*Last updated: December 2025*