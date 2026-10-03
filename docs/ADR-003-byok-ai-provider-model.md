# ADR-003: On-device AI by default, bring-your-own-key cloud providers

## Status
Accepted (revised 2026-10-04: provider APIs and on-device behavior verified)

## Date
2026-10-03

## Context
The owner decided:
- We ship a list of providers and models.
- The learner creates an API key with the provider and enters it in the app. They can use any model
  from the list, or the on-device model.
- The **Apple on-device model is the default**. A key is optional.

AI is used for:
1. The meaning of a term **in its sentence**, with a translation into the learner's native language.
   VocOrbit's core feature: "cookie" on a website is not "cookie" in milk.
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
     - `OpenAICompatibleClient` (OpenAI, Gemini through its OpenAI-compatible endpoint, DeepSeek,
       OpenRouter, Mistral, custom/local);
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
   | DeepSeek | `deepseek-flash` | |
   | OpenRouter | `google/gemini-3.1-flash-lite`, `openai/gpt-6-luna`, `deepseek/deepseek-v4.1-flash`, `mistralai/mistral-small-2603` | |
   | Mistral | `mistral-small-latest`, `ministral-8b-latest` | |
   | Custom OpenAI-compatible | — | base URL chosen by the learner |

   - Each entry also has its key page URL, structured-output mode, token-limit field and image
     support.
   - The learner can refresh the model list from the provider (`GET …/models`) or type any model ID.
     Model IDs change often, so the catalog is data, not logic.
4. **On-device strategy:**
   - Small steps, one task per call:
     1. **Sense** (in English): situation, English gloss, lemma, part of speech.
     2. **Native:** translation, meaning, grammar note. Language names are injected through
        `DynamicGenerationSchema`.
     3. **Details**, on demand: examples, other meanings.
   - Greedy sampling for insight; `maximumResponseTokens` of at least 400; no regex guides; a fresh
     session per task.
   - Check `SystemLanguageModel.default.availability` and `supportedLanguages` before offering
     on-device AI for a language.
5. **Cloud strategy:**
   - One call returns the full insight schema.
   - Quiz and podcast are generated in batches.
   - OpenAI uses `max_completion_tokens`. OpenRouter sends `provider.require_parameters: true` and an
     `X-OpenRouter-Title: Vocabulary-OS` header.
   - DeepSeek uses `json_object`, with the schema and an example embedded in the prompt.
6. **Validation everywhere:**
   - Every output passes a validator for language, length, required words and option sets before it
     is shown or stored.
   - On failure there is one retry with a corrective note, then a clear error.
7. **Selection and fallback:**
   - One active provider and model. The default is on-device when it's available.
   - If on-device is unavailable (device not eligible, Apple Intelligence off, model not ready, or the
     language unsupported), the app explains why and suggests connecting a provider.
   - There is no silent fallback between providers. Errors offer "Retry" and "Use on-device model".
8. **Keys and privacy:**
   - Keys live in the Keychain (ADR-002) and are only sent to the host of the provider they belong to.
   - Custom endpoints may use `http` only for local network hosts (`NSAllowsLocalNetworking`).
   - Before the first cloud call, the app shows what is sent:
     - **insight:** term, sentence, language names;
     - **quiz:** words and their meanings;
     - **podcast:** words;
     - **object:** the chosen label. The photo is sent only if spec open question 3 is answered yes.
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
- Adding a provider that speaks Chat Completions is a catalog entry, not code.
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
