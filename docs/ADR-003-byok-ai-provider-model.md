# ADR-003: On-device AI by default, bring-your-own-key cloud providers

## Status
Accepted (revised 2026-10-04: provider APIs and on-device behavior verified; the owner asked for the
popular providers and for providers the learner adds)

## Date
2026-10-03

## Context
The owner decided:
- We ship a list of providers and models: the popular ones (answer to spec question 4).
- The learner can also add their own provider (same answer).
- The learner creates an API key with the provider and enters it in the app. They can use any model
  from the list, or the on-device model.
- The **Apple on-device model is the default**. A key is optional.

AI is used for:
1. The meaning of a term **in its sentence**, with a translation into the learner's native language.
   The app's core feature: "cookie" on a website is not "cookie" in milk.
2. Breaking ties when a lone word's language is ambiguous (ADR-004).
3. Naming a photographed object in a learning language (ADR-005).
4. Generating quizzes.
5. Generating podcast scripts.

Facts that shape the design:
- **The on-device model:**
  - It has about 3 billion parameters, quantized to 2 bits.
  - It has a **4,096-token context** that holds instructions, schema, prompt and output.
  - Apple says it is "not designed for world knowledge or advanced reasoning" and that tasks should be
    broken into smaller pieces.
  - It supports the Apple Intelligence languages. On macOS 26.5 that is 23 locales, including tr, de,
    en, es, fr, it, pt, nl, sv, da, nb, ja, ko, zh and vi.
- **Prompt experiments on device, 2026-10-04:**
  - A single generic prompt with static "NATIVE language" guides answered German→Turkish cases in
    English, and took "Bank im Park" to be a financial institution.
  - Injecting the language names into the schema with `DynamicGenerationSchema` fixed the output
    language.
  - Adding a reasoning field first (the situation, then an English gloss of the sense) fixed the
    "bench"/"bank" and "pitch" senses.
  - Regex (`.pattern`) guides made every request fail with an internal error.
  - A low `maximumResponseTokens` truncated the JSON and caused `decodingFailure`.
  - Typical latency was 0.8–2 s per call.
- **Structured outputs:**
  - `GenerationSchema` is `Codable` and encodes to JSON Schema: `type: object`, `properties`,
    `required` (all fields), `additionalProperties: false`, `enum` for `anyOf` guides,
    `minItems`/`maxItems` for count guides, plus `title` and `x-order`.
  - `GeneratedContent(json:)` and the `Generable` initializer parse a cloud reply into the same Swift
    type. A missing field throws `decodingFailure`.
- **Cloud APIs differ in incompatible ways** (verified 2026-10-04, sources below):

  | Provider | Endpoint and auth | Structured output | Token limit field | Images |
  | --- | --- | --- | --- | --- |
  | OpenAI | `POST https://api.openai.com/v1/chat/completions`, Bearer | `response_format: json_schema`, strict | `max_completion_tokens` (`max_tokens` deprecated) | data URL |
  | Google Gemini | OpenAI-compatible `https://generativelanguage.googleapis.com/v1beta/openai/`, Bearer | `json_schema` (beta endpoint; enforcement not confirmed) | `max_tokens` | data URL |
  | DeepSeek | `https://api.deepseek.com/chat/completions`, Bearer | **`json_object` only**; the prompt must contain "json" and an example | `max_tokens` | `deepseek-flash` only |
  | OpenRouter | `https://openrouter.ai/api/v1/chat/completions`, Bearer | `json_schema` strict + `provider.require_parameters: true` | `max_tokens` | per model |
  | Mistral | `https://api.mistral.ai/v1/chat/completions`, Bearer | `json_schema` (`strict` defaults to false; we send true) | `max_tokens` | per model |
  | Local (Ollama `:11434/v1`, LM Studio `:1234/v1`) | no key | `json_schema` (LM Studio documented; Ollama not confirmed) | `max_tokens` | Ollama base64 only |
  | Anthropic | `POST https://api.anthropic.com/v1/messages`, `x-api-key`, `anthropic-version: 2023-06-01` | `output_config.format: {type: json_schema}` (GA). **Forced `tool_choice` returns 400 on the newest models.** | `max_tokens` (required) | base64 block |
  | xAI | `https://api.x.ai/v1`, Bearer (Chat Completions is marked legacy but has no end date) | `json_schema` strict | `max_completion_tokens` | data URL |
  | Alibaba Qwen | `https://dashscope-intl.aliyuncs.com/compatible-mode/v1`, Bearer; keys work only in their region | **`json_object` only** in this region; "json" must be in the prompt; no token limit with JSON output; thinking on by default (`enable_thinking: false`) | `max_completion_tokens` | data URL |
  | Moonshot Kimi | `https://api.moonshot.ai/v1`, Bearer | `json_schema` strict; `temperature` must not be sent | `max_completion_tokens` | base64 only |
  | Z.ai GLM | `https://api.z.ai/api/paas/v4`, Bearer | **`json_object` only**, text models only; thinking on by default (`thinking: {type: disabled}`) | `max_tokens` | vision models only |
  | Cohere | `https://api.cohere.ai/compatibility/v1`, Bearer | **`{type: json_object, schema}`**; OpenAI's `json_schema` shape returns 400; no `minItems` | `max_tokens` | not documented |
  | Groq | `https://api.groq.com/openai/v1`, Bearer | `json_schema` strict on gpt-oss and Qwen 3.8 | `max_completion_tokens` | Qwen 3.8 only |
  | Cerebras | `https://api.cerebras.ai/v1`, Bearer | `json_schema` strict; **no `minItems`/`maxItems`** | `max_completion_tokens` | Qwen 3.8 only, base64 |
  | Together AI | `https://api.together.ai/v1`, Bearer | `json_schema` (strict subset undocumented) | `max_tokens` | data URL; **`/models` is a bare array** |
  | Fireworks AI | `https://api.fireworks.ai/inference/v1`, Bearer | `json_schema`, enforced | `max_tokens` (default 2048) | data URL; model IDs start with `accounts/fireworks/models/` |
  | Hugging Face | `https://router.huggingface.co/v1`, Bearer (fine-grained token) | `json_schema`; enforcement depends on the host, so models pin one (`model:host`) | `max_tokens` | data URL |

- **Error bodies differ too:**
  - OpenAI: `{"error":{…}}`.
  - Anthropic: `{"type":"error","error":{…}}`.
  - Gemini-compat: a JSON **array**.
  - DeepSeek: plain text on 401.

## Decision
1. **One contract, three wire families.**
   - `GenerationClient` generates any `@Generable` output type, plus dynamic schemas.
   - Implementations:
     - `AppleOnDeviceClient` (FoundationModels);
     - `OpenAICompatibleClient` (OpenAI, Gemini through its OpenAI-compatible endpoint and every
       other listed provider but Anthropic, and the learner's own providers);
     - `AnthropicClient` (Messages API with `output_config.format`).
   - No provider SDKs.
2. **Outputs are defined once** as `@Generable` structs:
   - insight (sense, native and details steps);
   - language guess;
   - object name;
   - quiz question;
   - podcast script.

   Cloud clients get the schema by encoding `T.generationSchema`. It is sanitized per provider:
   - drop `title` and `x-order`;
   - for Anthropic, also drop `minItems`/`maxItems`, which validators enforce instead.

   Replies are parsed with `GeneratedContent(json:)` after tolerant extraction (code fences, leading
   text, the first JSON object in a `text` block, skipping Anthropic `thinking` blocks).
3. **Provider catalog** (one Swift file, `lastVerified` date in a comment):

   | Provider | Recommended models (verified 2026-10-04) | Notes |
   | --- | --- | --- |
   | Apple on device | system model | no key |
   | OpenAI | `gpt-6-luna`, `gpt-5.4-nano`, `gpt-5.4-mini` | |
   | Anthropic | `claude-haiku-4-5`, `claude-sonnet-5-5` | |
   | Google Gemini | `gemini-3.1-flash-lite`, `gemini-3.5-flash-lite`, `gemini-3.8-flash` | |
   | xAI | `grok-4.3`, `grok-4.20-0309-non-reasoning` | |
   | DeepSeek | `deepseek-flash` | |
   | Mistral | `mistral-small-latest`, `ministral-8b-latest` | |
   | Alibaba Qwen | `qwen3.8-flash`, `qwen3.7-flash`, `qwen-flash` | thinking turned off |
   | Moonshot Kimi | `kimi-k2.6`, `kimi-k3` | prepaid, low limits at the first tier |
   | Z.ai GLM | `glm-4.7-flashx`, `glm-4.7-flash` | text only; thinking turned off |
   | Cohere | `command-r-08-2024`, `command-a-03-2025` | trial keys: 1,000 calls a month |
   | Groq | `openai/gpt-oss-120b`, `openai/gpt-oss-20b`, `qwen/qwen3.8-27b` | |
   | Cerebras | `gpt-oss-120b`, `qwen-3.8-27b` | |
   | Together AI | `openai/gpt-oss-120b`, `Qwen/Qwen3.5-9B`, `deepseek-ai/DeepSeek-V4.1-Flash` | |
   | Fireworks AI | `accounts/fireworks/models/glm-5p3-flash`, `…/deepseek-v4p1-flash`, `…/gpt-oss-120b` | |
   | Hugging Face | `openai/gpt-oss-120b`, `zai-org/GLM-5.3-Flash:baseten`, `deepseek-ai/DeepSeek-V4.1-Flash:baseten` | |
   | OpenRouter | `google/gemini-3.1-flash-lite`, `openai/gpt-6-luna`, `deepseek/deepseek-v4.1-flash`, `mistralai/mistral-small-2603` | |

   Not listed, checked on 2026-10-04:
   - Perplexity: Sonar's Chat Completions reached end of support on 2026-09-27; its successor
     speaks the Responses API, and its Chat Completions router is in private preview.
   - Meta's Llama API shut down on 2026-07-06; its successor, the Meta Model API, is a public
     preview whose cheapest model trains on the prompts it gets.
   - MiniMax offers no structured output on Chat Completions.
   - Azure OpenAI and Amazon Bedrock have an address per resource or region; learners add them as
     their own providers.

   Every listed provider's request shape is checked against its documentation by a stubbed-network
   test; none has been tried with a real key yet.
4. **Providers the learner adds:**
   - Any service with an OpenAI-compatible Chat Completions API: a name, an address (the part before
     `/chat/completions`) and an optional key. Ollama, LM Studio, Azure OpenAI, Amazon Bedrock and
     company gateways all fit.
   - Requests use a JSON Schema that isn't strict and send no output limit, since such servers
     disagree on what they accept (Azure's reasoning models reject `max_tokens`).
   - Plain `http` is accepted only for this device and the local network; elsewhere the address must
     be `https`, so the key and the learner's words travel encrypted.
   - A key is stored under the provider's own ID and only ever goes to the server it was entered
     for: moving the provider to another host, port or scheme removes its key.
   - The providers sync with the settings and their keys with iCloud Keychain. Choosing a provider
     at `localhost` changes only that device's choice (ADR-002), since the others can't reach it.

   - Each entry also has its key page URL, structured-output mode, token-limit field and image
     support.
   - The learner can refresh the model list from the provider (`GET …/models`) or type any model ID.
     Model IDs change often, so the catalog is data, not logic.
5. **On-device strategy:**
   - Small steps, one task per call:
     1. **Sense** (in English): situation, English gloss, lemma, part of speech.
     2. **Native:** translation, meaning, grammar note. Language names are injected through
        `DynamicGenerationSchema`.
     3. **Details**, on demand: examples, other meanings.
   - Greedy sampling for insight; `maximumResponseTokens` of at least 400; no regex guides; a fresh
     session per task.
   - Check `SystemLanguageModel.default.availability` and `supportedLanguages` before offering
     on-device AI for a language.
6. **Cloud strategy:**
   - One call returns the full insight schema.
   - Quiz and podcast are generated in batches.
   - OpenAI uses `max_completion_tokens`. OpenRouter sends `provider.require_parameters: true` and an
     `X-OpenRouter-Title: Vocabulary-OS` header.
   - DeepSeek, Qwen and Z.ai use `json_object`, with the schema and an example embedded in the
     prompt; Cohere gets the schema in its own `json_object` form.
   - Array bounds are dropped for providers whose strict mode rejects them; validators check counts.
   - The output limit is at least 8,192 tokens, since many models now reason by default and count
     that against it. It caps cost, not the answer. Qwen and Z.ai models are asked not to think.
   - Reasoning that a model writes into its answer between `<think>` tags is dropped before the
     JSON is read.
7. **Validation everywhere:**
   - Every output passes a validator for language, length, required words and option sets before it
     is shown or stored.
   - On failure there is one retry with a corrective note, then a clear error.
8. **Selection and fallback:**
   - One active provider and model. The default is on-device when it's available.
   - If on-device is unavailable (device not eligible, Apple Intelligence off, model not ready, or the
     language unsupported), the app explains why and suggests connecting a provider.
   - There is no silent fallback between providers. Errors offer "Retry" and "Use on-device model".
9. **Keys and privacy:**
   - Keys live in the Keychain (ADR-002) and are only sent to the host of the provider they belong to.
   - The learner's own providers may use `http` only for this device and the local network
     (`NSAllowsLocalNetworking`, and the address check in item 4).
   - Before the first cloud call, the app shows what is sent:
     - **insight:** term, sentence, language names;
     - **quiz:** words and their meanings;
     - **podcast:** words;
     - **object:** the chosen label, and the photo when the learner turns on sending object photos
       (ADR-005).
   - Generated insight is stored on the word, so repeated views make no new calls.

## Alternatives Considered
- **Hosted backend that calls AI for users (SaaS):**
  - Needs a server, costs us money and would see every request.
  - Rejected by the owner.
- **Provider SDKs:**
  - Several dependencies for what are two HTTP request shapes.
  - Rejected (ADR-006: no third-party runtime dependencies).
- **OpenAI Responses API:**
  - Recommended by OpenAI for new projects, but Chat Completions "remains supported" and is the
    shape every other provider here implements.
  - Rejected for v1 to keep one client.
- **Anthropic forced tool use:**
  - Returns 400 on the newest Claude models.
  - Rejected in favor of `output_config.format`.
- **Native Gemini `generateContent`:**
  - Its documentation conflicts about the `mimeType` value.
  - Deferred. The OpenAI-compatible endpoint is used, and validators catch schema drift.
- **One large on-device prompt:**
  - Measured as wrong-language and wrong-sense prone.
  - Rejected in favor of small steps.

## Consequences
- Works offline and for free on Apple-Intelligence devices. Quality is lower than cloud models, so
  the UI says so and makes connecting a provider easy.
- Adding a provider that speaks Chat Completions is a catalog entry, plus a quirk when it differs.
  Providers we don't list can still be used, by adding them as the learner's own.
- Model IDs go stale. The catalog needs review each release, and live listing covers the gaps.
- On-device prompts must be re-evaluated (`vos-eval`) when Apple ships a new model version: the
  model changes with 26.4 and 27.0.
- Validators and retries add latency on failure, but keep bad AI output out of the learner's data.

## Sources
- Apple:
  - Foundation Models context window:
    https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window
  - Model size and intended tasks: https://developer.apple.com/videos/play/wwdc2025/286/
  - Prompting the on-device model:
    https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model
  - Languages:
    https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models
  - `GenerationSchema`, `DynamicGenerationSchema`, `GeneratedContent(json:)`: `FoundationModels.swiftinterface`,
    macOS 26.2 SDK
- OpenAI:
  - Chat Completions: https://developers.openai.com/api/reference/resources/chat
  - Structured outputs: https://developers.openai.com/api/docs/guides/structured-outputs
  - Models: https://developers.openai.com/api/docs/models
  - Error codes: https://developers.openai.com/api/docs/guides/error-codes
- Anthropic:
  - Messages: https://platform.claude.com/docs/en/api/messages/create
  - Structured outputs: https://platform.claude.com/docs/en/build-with-claude/structured-outputs
  - Tool choice changes: https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools
  - Errors: https://platform.claude.com/docs/en/api/errors
  - Models list: https://platform.claude.com/docs/en/api/models/list
- Google Gemini:
  - OpenAI compatibility: https://ai.google.dev/gemini-api/docs/openai
  - Structured output: https://ai.google.dev/gemini-api/docs/generate-content/structured-output
  - Models: https://ai.google.dev/gemini-api/docs/models
- DeepSeek:
  - API: https://api-docs.deepseek.com/
  - JSON mode: https://api-docs.deepseek.com/guides/json_mode
  - Vision: https://api-docs.deepseek.com/guides/vision
- OpenRouter:
  - Quickstart: https://openrouter.ai/docs/quickstart
  - Structured outputs: https://openrouter.ai/docs/guides/features/structured-outputs
  - Errors: https://openrouter.ai/docs/api_reference/errors-and-debugging
- Mistral:
  - Structured output: https://docs.mistral.ai/studio/conversations/structured-output/custom
  - Errors: https://docs.mistral.ai/resources/error-glossary
- Local servers:
  - Ollama: https://docs.ollama.com/api/openai-compatibility
  - LM Studio: https://lmstudio.ai/docs/developer/openai-compat/structured-output
- xAI: https://docs.x.ai/developers/rest-api-reference/inference/chat-completions ,
  https://docs.x.ai/developers/model-capabilities/text/structured-outputs ,
  https://docs.x.ai/developers/models
- Alibaba Qwen: https://www.alibabacloud.com/help/en/model-studio/qwen-api-via-openai-chat-completions ,
  https://www.alibabacloud.com/help/en/model-studio/qwen-structured-output ,
  https://www.alibabacloud.com/help/en/model-studio/regions
- Moonshot Kimi: https://platform.kimi.ai/docs/api/chat , https://platform.kimi.ai/docs/guide/response_format ,
  https://platform.kimi.ai/docs/api/models-overview
- Z.ai: https://docs.z.ai/api-reference/llm/chat-completion , https://docs.z.ai/guides/capabilities/struct-output ,
  https://docs.z.ai/guides/capabilities/thinking-mode
- Cohere: https://docs.cohere.com/docs/compatibility-api , https://docs.cohere.com/docs/structured-outputs
- Groq: https://console.groq.com/docs/openai , https://console.groq.com/docs/structured-outputs ,
  https://console.groq.com/docs/models
- Cerebras: https://inference-docs.cerebras.ai/resources/openai ,
  https://inference-docs.cerebras.ai/capabilities/structured-outputs
- Together AI: https://docs.together.ai/docs/inference/openai-compatibility ,
  https://docs.together.ai/reference/models
- Fireworks AI: https://docs.fireworks.ai/tools-sdks/openai-compatibility ,
  https://docs.fireworks.ai/structured-responses/structured-response-formatting
- Hugging Face: https://huggingface.co/docs/inference-providers/tasks/chat-completion ,
  https://huggingface.co/docs/inference-providers/guides/structured-output
- Not listed: https://docs.perplexity.ai/docs/agent-api/migrate-from-sonar/overview ,
  https://llama.developer.meta.com/docs/llama-api-deprecation/ ,
  https://platform.minimax.io/docs/api-reference/text-chat-openai ,
  https://learn.microsoft.com/en-us/azure/foundry/openai/api-version-lifecycle ,
  https://docs.aws.amazon.com/bedrock/latest/userguide/inference-chat-completions.html
