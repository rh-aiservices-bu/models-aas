# APIcast LLM Metrics Policy

## What is it?

Custom policy to monitor LLM model token usage using APIcast

## How to use it?

Everything is included in a policy, no custom image is needed.

Simply add the custom policy as described in the [Readme](../../../README.md).

Configuration parameters:

- SSE support: checked to enable token counts for Streaming responses.
- Increment: `{{llm_usage.total_tokens}}`
- Left: `{{status}}`
- Left-type: Liquid
- Right: `200`
- Right-type: Plain text
- op: `==`
- Metric to increment: `total_tokens`

In the same policy, add the same rules for `prompt_tokens` and `completion_tokens` respectively.

## How does it work?

This policy does a few things:

- Expose AI model token usage via Prometheus metrics
- Support sending custom metrics to 3scale
- Handle Server Send Event (SSE) response

Not supported:

- Gzip payload

## Prometheus metrics

Once the policy is added to the product, it will display the following 3 metrics:

- `prompt_tokens`
- `completions_token`
- `total_tokens`

Each metric is implemented as a counter and scoped by Product by default. The metrics will have the following format.

```text
name: prompt_tokens labels(application_id, application_name, service_id, service_name) value=prompt_tokens

name: completion_tokens labels(application_id, application_name, service_id, service_name) value=completion_tokens

name: total_tokens labels(application_id, application_name, service_id, service_name) value=total_tokens
```

For example:

$ curl <APICast_IP>:9421/metrics

```log
...
# HELP llm_completion_tokens_count Token count for a completion 
# TYPE llm_completion_tokens_count counter
llm_completion_tokens_count{service_id="1",service_system_name="",application_id="1",application_system_name="test"} 16
# HELP llm_prompt_tokens_count Token count for a prompt
# TYPE llm_prompt_tokens_count counter
llm_prompt_tokens_count{service_id="1",service_system_name="",application_id="1",application_system_name="test"} 24 
# HELP llm_total_token_count Total token count
# TYPE llm_total_token_count counter
llm_total_token_count{service_id="1",service_system_name="",application_id="1",application_system_name="test"} 40
...
```

Note that to extract usage, the response is fully buffered into memory and then decoded to a LUA object. So increase the memory request/limit if you start seeing performance issues.

## Custom metrics

To avoid patching the existing Custom Metrics policy, in is included this LLM policy. The functionality and usage is identical to the built-in Custom Metrics policy, but there are a few additional fields exposed in the request context:

- Token usage
- Application details

NOTE: Metrics need to be created in the Admin Portal before the policy will push the metric values.

For example: the following configuration will set up a metric call total_tokens with increment based on the total_tokens used.

```json
{
    "name": "apicast.policy.llm", 
    "configuration": {
    "rules": [{
        "condition": {
        "operations": [
            {"op": "==", "left": "{{status}}", "left_type": "liquid", "right": "200"}
        ],
        "combine_op": "and"
        },
        "metric": "total_tokens",
        "increment": "{{ llm_usage.total_tokens }}"
    }]
    }
}
```

## Server-send events (SSE)

Streaming is a mode where a client can specify "stream": true in their request, and the LLM server will stream each piece of the response (usually token-by-token) as a server-sent event (SSE).

We need to do three things here:

- Parse the incoming request and check whether stream: true is set
- Detect the stream response based on the header text/event-stream
- Parse the events and detect the usage token

SSE support is off by default, toggle the SSE support checkbox to enable

NOTE: Streamed responses will not be buffered, instead being streamed back to the client.
