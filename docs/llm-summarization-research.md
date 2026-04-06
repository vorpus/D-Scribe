# Local LLM-Powered Meeting Summarization: Research Findings

> Date: 2026-04-05
> Status: Research (no code changes)

---

## Topic 1: Off-the-Shelf Models for Meeting Summarization

### Model Landscape Overview

The small/local LLM space has matured significantly. Several model families in the 1B-8B range now produce usable meeting summaries when run entirely on-device via Apple Silicon. The key families to evaluate are:

### Recommended Models (Ranked by Suitability)

#### Tier 1: Best Candidates

**Gemma 4 26B-A4B (MoE)** -- The standout option if hardware allows.
- Architecture: Mixture of Experts, 26B total parameters but only **3.8B active per token**
- Runs at roughly the speed of a 4B dense model with the knowledge capacity of a 25B model
- LMArena score: 1441 (frontier-level -- the 31B dense scores 1452)
- RAM: ~15.6 GB at Q4 quantization. Tight on 16GB Macs, comfortable on 24GB+
- Speed: ~20-30 tok/s on Apple Silicon
- Hybrid attention (sliding window + global) is well-suited for long meeting transcripts
- Day-one support for MLX, llama.cpp, Ollama, LM Studio
- **Verdict: Best quality-to-compute ratio available. If the user has 24GB+ RAM, this is the top pick.**

**Gemma 4 E4B** -- Best for 16GB Macs.
- 8B total parameters, 4.5B effective, 128K context
- RAM: ~5 GB at Q4 quantization -- leaves room for the rest of D Scribe, macOS, browser, etc.
- First model under 10B parameters to achieve LMArena score over 1300
- Excellent summarization out of the box as a Gemma family strength
- **Verdict: The practical default for most Mac users. Fast, small, capable.**

**Gemma 3n E4B** -- Alternative if Gemma 4 E4B is unavailable or too large.
- Designed specifically for on-device/low-resource execution
- Runs with as little as **3 GB of memory** via MatFormer architecture (nested sub-models)
- Per-Layer Embeddings (PLE) technology further reduces runtime memory
- LMArena score over 1300
- Meetily (open-source meeting app) specifically recommends this for "strong summarization capabilities"
- **Verdict: Best option for memory-constrained (8GB) Macs.**

#### Tier 2: Strong Alternatives

**Qwen 3.5 4B**
- IFEval score of 89.8% (higher than GPT-OSS-120B at 88.9%, a model 30x its size)
- Consistent performance across classification, code, and summarization without "cratering" on complex tasks
- Good multilingual support
- Competitive with Gemma 3 4B and Llama 3.2 3B on instruction-following benchmarks
- **Verdict: Strong contender, especially if multilingual meeting support matters.**

**SmolLM3 3B** (Hugging Face)
- Outperforms Llama-3.2-3B and Qwen2.5-3B at the 3B scale
- 128K token context window
- Explicitly positioned for "fast dialogue, summarization, retrieval-style tasks"
- Fully open weights and training recipe
- **Verdict: Good lightweight option. Easy to fine-tune given full openness.**

**Llama 3.2 3B**
- Matches larger Llama 3.1 8B on tool use and **exceeds it on summarization** (TLDR9+ benchmark)
- Only 1.9 GB as GGUF, 128K context
- 10-25 tok/s on Apple Silicon
- Well-tested ecosystem (Ollama, llama.cpp, MLX all mature)
- **Verdict: Battle-tested, tiny footprint, surprisingly good at summarization specifically.**

#### Tier 3: Specialized / Niche

**SummLlama3.2-3B** (DISLab on Hugging Face)
- Llama 3.2 3B fine-tuned with DPO on **100K+ summarization feedback examples**
- Trained across 7 domains including **meeting transcripts** specifically
- Optimized for faithfulness, completeness, and conciseness
- **Verdict: The only pre-fine-tuned meeting summarization model at this size. Worth testing head-to-head against base Gemma 4 E4B.**

**Phi-4 Mini** (Microsoft, 3.8B parameters)
- Includes "significantly larger and more diverse set of function calling and summarization data" vs Phi-3.5
- Mixture-of-LoRAs architecture
- **Verdict: Competitive but Gemma 4 and Qwen 3.5 have pulled ahead in benchmarks.**

**Mistral Small**
- Efficient and lightweight, well-suited for fast local inference
- Less benchmark data available for summarization specifically
- **Verdict: Viable but not the leader in this category anymore.**

### Apple Silicon Inference Performance

| Framework | Typical Speed (small models) | Notes |
|-----------|------------------------------|-------|
| **MLX** | ~230 tok/s | 20-87% faster than llama.cpp for models under 14B. Apple-native, zero-copy unified memory. |
| **MLC-LLM** | ~190 tok/s | Good middle ground |
| **llama.cpp** | ~150 tok/s (short context) | Most mature ecosystem, direct Metal API calls, best resource utilization |
| **Ollama** | 20-40 tok/s | Convenience wrapper around llama.cpp, overhead is significant |
| **PyTorch MPS** | ~7-9 tok/s | Not recommended for production |

Key hardware factors:
- M4 Pro bandwidth: 273 GB/s (every parameter must be read from memory each token)
- M4 Max bandwidth: ~400 GB/s
- At Q4 quantization, a 4B model fits in ~2-3 GB, an 8B model in ~5-6 GB
- MLX outperforms GGUF-based inference on the same Apple Silicon hardware for models that fit comfortably in memory

**Recommendation for D Scribe:** Use MLX as the inference backend. It is purpose-built for Apple Silicon, has the best throughput for models under 14B, and Apple themselves showcased it at WWDC25 for exactly this use case. Ollama is convenient for prototyping but adds significant overhead.

### Quality: Small Models vs Large

The gap has narrowed dramatically in 2025-2026:
- Gemma 4 26B-A4B (running at 4B active params) competes with models 20x its total size
- Llama 3.2 3B exceeds Llama 3.1 8B on summarization benchmarks
- For meeting summarization specifically, 3-4B models produce usable summaries; 8B+ models produce good summaries; the 26B MoE produces excellent summaries

The practical quality floor for "useful meeting summary" is around 3B parameters with a good instruction-tuned model and a well-crafted prompt.

---

## Topic 2: Fine-Tuning vs Off-the-Shelf

### What Research Says

The consensus from 2025-2026 research is nuanced:

1. **For general summarization, prompting is often sufficient.** Modern instruction-tuned models achieve competitive performance in zero-shot and one-shot settings, often approaching fine-tuned baselines. The gap between fine-tuned and prompted approaches has narrowed considerably with more capable foundation models.

2. **For domain-specific summarization, fine-tuning still helps.** Clinical research (JMIR 2025) found that SFT (supervised fine-tuning) alone strengthens simple word-association reasoning, but DPO (direct preference optimization) enables more nuanced interpretation -- important for tasks like meeting summarization where context and priorities matter.

3. **The practical recommendation:** Start with prompt engineering. If quality is insufficient, fine-tune with LoRA/QLoRA. The research paper "Tell me what I need to know" (arXiv:2410.14545) demonstrated that **Phi-3 mini 128k produces good-quality meeting summaries in a zero-shot setup**, suggesting even small models can work well with good prompts.

### When Fine-Tuning IS Worth It

- **Consistent output format:** If you need summaries in a specific structure (action items, decisions, key topics) every time, fine-tuning enforces this more reliably than prompts alone.
- **Domain terminology:** If the user's meetings use specialized jargon (engineering, legal, medical), fine-tuning on domain-specific transcripts helps.
- **Personalization at scale:** The SummLlama3.2-3B model demonstrates that DPO on 100K+ summarization examples yields "significant improvements" in faithfulness, completeness, and conciseness over the base model.
- **Reducing prompt length:** A fine-tuned model may not need a long system prompt, saving context window for the actual transcript.

### When Fine-Tuning is NOT Worth It

- **General meeting summaries with a good model:** Gemma 4 E4B or 26B-A4B with a well-crafted system prompt will likely be sufficient for most users.
- **Limited training data:** If you have fewer than ~200 high-quality transcript-summary pairs, the improvement may be marginal.
- **Rapidly changing requirements:** If the summary format or focus areas change frequently, re-prompting is far easier than re-training.

### Available Training Data

| Dataset | Size | Description |
|---------|------|-------------|
| **MeetingBank** | 1,366 meetings (3,579 hours), 6,892 segment-level instances | City council meetings with transcripts + minutes. Long-form (avg 28K tokens per transcript). CC-licensed. |
| **AMI Corpus** | 279 dialogues | Business meeting recordings with abstractive summaries. CC BY 4.0. |
| **DialogSum** | 13,460 dialogues (+1,000 test) | General dialogue summarization. Good for augmenting meeting-specific data. |
| **QMSum** | Query-based meeting summarization | Supports targeted/personalized summarization (ask specific questions about meetings). |

Pre-fine-tuned models already available:
- **SummLlama3.2-3B** -- DPO-tuned on 100K+ examples across 7 domains including meetings
- **SummLlama3.1-8B** -- Same approach, larger model
- **Llama-Chat-Summary-3.2-3B** -- Chat-focused summarization
- **BART-QMSum** -- Fine-tuned for query-based meeting summarization
- Various BART/T5 models fine-tuned on AMI+SAMSum

### Fine-Tuning on Mac: Practical Guide

**Primary tool: MLX + LoRA**

MLX is the clear winner for Mac-native fine-tuning:
- Built by Apple ML Research specifically for unified memory architecture
- Zero memory copies between CPU and GPU
- On a 16GB M2 MacBook Pro: fine-tune a LoRA adapter on a custom dataset in **under 30 minutes**
- Supports QLoRA (4-bit base model + 16-bit LoRA adapters)
- Data format: JSONL files (train.jsonl, valid.jsonl)
- Apple showcased MLX fine-tuning at WWDC25

**Unsloth:** NOT natively supported on Mac yet (requires Triton, which macOS lacks). However, **mlx-tune** provides an Unsloth-compatible API wrapper around MLX, allowing code portability between Mac and CUDA.

**Data requirements for LoRA fine-tuning:**
- Minimum viable: ~200-500 high-quality examples (transcript excerpt + expected summary)
- Good results: 1,000-5,000 examples
- Excellent results: 4,000-6,000+ examples (with 3-4 training epochs)
- Quality matters more than quantity -- LoRA is especially sensitive to noisy or inconsistent data
- Each example should be formatted as an instruction-response pair matching your production use case

### Cost/Benefit Analysis

| Approach | Effort | Quality Gain | Recommended When |
|----------|--------|--------------|------------------|
| Prompt engineering only | Low (hours) | Baseline | Start here always |
| Use pre-fine-tuned model (SummLlama3.2-3B) | Very low | Moderate over base Llama 3.2 | Want better summarization without any training |
| LoRA fine-tune on MeetingBank + AMI | Medium (days) | Moderate-High | Need consistent format, domain adaptation |
| LoRA fine-tune on user's own meetings | High (weeks to collect data) | Highest | User has specific formatting/focus needs |
| DPO after initial SFT | High | Highest for preference alignment | Need summaries tailored to user taste |

**Practical recommendation for D Scribe:** Ship with prompt engineering on Gemma 4 E4B (or 26B-A4B for capable hardware). Offer SummLlama3.2-3B as an alternative. Consider adding LoRA fine-tuning as a power-user feature later, once the summarization prompt and format are stabilized.

---

## Topic 3: Personalized / Context-Aware Summarization

### The Research Landscape

Two key papers directly address this problem:

#### Paper 1: "Tell me what I need to know" (arXiv:2410.14545, Oct 2024)

This paper presents a three-step RAG-based pipeline for personalized meeting summarization:

1. **Gap Identification:** An LLM instance analyzes the transcript to find passages where a reader might lack context, using chain-of-thought reasoning.
2. **Information Inferring:** A RAG module retrieves supplementary information (documents, prior meeting notes, project context) to fill identified gaps.
3. **Personalization Protocol:** Extracts participant personas dynamically from the transcript, then generates summaries tailored to a specific reader's role.

Key results:
- Multi-source RAG improved summary quality by **0.31-0.42** over single-source baselines
- Persona-based personalization improved relevance by **up to 0.44** over role-only baselines
- Works in zero-shot with models as small as **Phi-3 mini 128K**
- The persona extraction is dynamic (pulled from the transcript itself), not just a static profile

#### Paper 2: "PLUS: Preference Learning Using Summaries" (arXiv:2507.13579, Microsoft Research, 2025-2026)

A general framework for personalizing LLM responses using learned user summaries:

- Uses RL to learn text-based summaries of each user's preferences, characteristics, and conversation history
- These summaries condition the reward model for personalized predictions
- **11-77% improvement** in reward model accuracy vs standard Bradley-Terry
- **25% improvement** over best personalized reward model for RLHF
- Zero-shot personalization: PLUS-conditioned responses achieve **72% win rate** vs default GPT-4o
- User summaries are **interpretable** -- users can read and edit their own preference profiles

### Practical Architecture for D Scribe

Based on the research, here is how personalization could work in D Scribe, ordered from simplest to most sophisticated:

#### Level 1: System Prompt with User Context (Ship First)

Maintain a "user context" document that the user fills in (or that builds up over time). Inject it into the system prompt before each summarization.

```
You are summarizing a meeting for [User Name], who is a [Role] at [Company].

Their key responsibilities include:
- [Responsibility 1]
- [Responsibility 2]

Their current focus areas:
- [Focus 1]
- [Focus 2]

When generating the summary:
1. Highlight decisions and discussions relevant to their role
2. Extract action items specifically assigned to them or their team
3. Flag topics outside their normal scope that might be stretch opportunities
4. Suggest concrete next steps they should take
5. Note any risks or blockers that could affect their work
```

This is zero-cost to implement, works with any model, and the "Tell me what I need to know" paper showed significant personalization gains from just providing role information.

#### Level 2: RAG with Meeting History + User Profile

Store previous meeting summaries and the user context document in a local vector database (SQLite with vector extension, or a simple embedding index). Before summarizing a new meeting:

1. Embed the new transcript
2. Retrieve relevant prior meeting context (decisions made, action items from last time)
3. Include retrieved context in the prompt alongside the user profile

This enables the model to:
- Track action item completion across meetings
- Reference prior decisions ("As decided in last week's standup...")
- Notice recurring topics and patterns
- Suggest follow-ups on previously discussed items

Meetily already implements this pattern with SQLite + VectorDB for semantic search over past meetings.

#### Level 3: Dynamic Persona Extraction (from the research)

Per the "Tell me what I need to know" paper, automatically extract participant personas from each transcript:
- Who participated and what were their apparent roles/concerns
- What topics each person focused on
- What each person committed to

This enables per-participant action items and personalized framing without the user manually maintaining profiles for every meeting participant.

#### Level 4: Learned User Preferences (Future / Advanced)

Based on the PLUS framework:
- Track which parts of summaries the user edits, expands, or deletes
- Use this implicit feedback to learn a "user preference summary" (a text description of what they care about)
- Condition future summarization on this learned profile
- The PLUS paper shows this can be done with modest computational overhead

### Addressing Specific Personalization Goals

**Understanding the user's role and responsibilities:**
- Level 1 (system prompt) handles this directly
- The user profile document should include: job title, team, reporting chain, key projects, recurring meeting types

**Focus areas and usual scope of work:**
- Level 1 system prompt with explicit focus areas
- Level 2 RAG can infer this from patterns in past meeting summaries
- Could auto-update: "You've been in 12 meetings about Project X this month -- adding to your focus areas"

**Recommendations on next steps:**
- Prompt engineering handles this well. The AssemblyAI and C# Corner guides show effective prompt structures for extracting action items with owners and due dates.
- Key prompt elements: "For each action item, specify: who is responsible, what needs to be done, suggested deadline based on discussion urgency, and dependencies on other items"

**Suggesting stretch opportunities beyond normal scope:**
- This is the most novel requirement. Approach:
  - In the user profile, explicitly list what IS their normal scope
  - In the summarization prompt, add: "Identify any discussion topics, projects, or initiatives mentioned in this meeting that fall OUTSIDE [User]'s listed responsibilities but where they could add value based on their skills in [X, Y, Z]. Flag these as 'Stretch Opportunities' with a brief explanation of why it might be relevant to them."
  - Level 2 RAG enhances this by knowing what the user has expressed interest in previously

### Existing Projects and Tools

| Project | Approach | Notes |
|---------|----------|-------|
| **Meetily** | Ollama + Whisper + SQLite/VectorDB | Open source, closest to D Scribe's architecture. Has semantic search over past meetings. |
| **Char** | Custom 1.1 GB HyperLLM-V1 model | Optimized specifically for summarization quality at tiny size |
| **AssemblyAI pipeline** | Transcript -> structured prompt -> LLM | Good reference for prompt engineering patterns |
| **PLUS framework** (Microsoft Research) | RL-learned user summaries | Academic but demonstrates the ceiling for personalization |

---

## Overall Recommendations for D Scribe

### Phase 1: Ship Quickly
1. **Model:** Gemma 4 E4B (default) with Gemma 4 26B-A4B as option for users with 24GB+ RAM
2. **Inference:** MLX backend (fastest on Apple Silicon, Apple-supported)
3. **Personalization:** System prompt with user context document (Level 1)
4. **Summary format:** Structured output with sections for Key Decisions, Action Items (with owners), Discussion Topics, and Next Steps

### Phase 2: Enhance
1. **RAG:** Add local vector store for meeting history context (Level 2)
2. **Alternative model:** Offer SummLlama3.2-3B for users who want a summarization-specialist model
3. **Dynamic personas:** Extract participant information from transcripts (Level 3)
4. **Stretch opportunities:** Add to prompt once user profile is established

### Phase 3: Advanced (If Warranted)
1. **LoRA fine-tuning:** Offer as power-user feature for customizing summary style
2. **Preference learning:** Track user edits to summaries, build preference profile (Level 4)
3. **Cross-meeting intelligence:** Action item tracking, recurring topic detection

---

## Sources

### Topic 1: Models
- [The Best Open Source LLMs for Summarization in 2026](https://www.siliconflow.com/articles/en/best-open-source-llms-for-summarization)
- [Best LLMs for Summarization (2026) + Evaluation Framework](https://clickup.com/blog/best-llms-for-language-summarization/)
- [The Best Open-Source Small Language Models (SLMs) in 2026](https://www.bentoml.com/blog/the-best-open-source-small-language-models)
- [Gemma 4 model card](https://ai.google.dev/gemma/docs/core/model_card_4)
- [Gemma 4: Byte for byte, the most capable open models](https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/)
- [Gemma 4 on Apple Silicon: All Four Models Compared](https://sudoall.com/gemma-4-31b-apple-silicon-local-guide/)
- [Gemma 4 Hardware Requirements](https://gemma4all.com/blog/gemma-4-hardware-requirements)
- [Gemma 3n model overview](https://ai.google.dev/gemma/docs/gemma-3n)
- [SmolLM3: smol, multilingual, long-context reasoner](https://huggingface.co/blog/smollm3)
- [SummLlama3.2-3B on Hugging Face](https://huggingface.co/DISLab/SummLlama3.2-3B)
- [Local Meeting Notes with Whisper + Ollama (Meetily)](https://dev.to/zackriya/local-meeting-notes-with-whisper-transcription-ollama-summaries-gemma3n-llama-mistral--2i3n)
- [Llama 3.2 3B on Ollama](https://ollama.com/library/llama3.2)

### Topic 1: Inference Performance
- [Production-Grade Local LLM Inference on Apple Silicon (arXiv:2511.05502)](https://arxiv.org/abs/2511.05502)
- [2026 Mac Inference Framework Selection: vllm-mlx vs Ollama vs llama.cpp](https://macgpu.com/en/blog/2026-mac-inference-framework-vllm-mlx-ollama-llamacpp-benchmark.html)
- [MLX vs llama.cpp on Apple Silicon](https://groundy.com/articles/mlx-vs-llamacpp-on-apple-silicon-which-runtime-to-use-for-local-llm-inference/)
- [Local LLMs Apple Silicon Mac 2026 Guide](https://www.sitepoint.com/local-llms-apple-silicon-mac-2026/)
- [Explore large language models on Apple silicon with MLX - WWDC25](https://developer.apple.com/videos/play/wwdc2025/298/)

### Topic 2: Fine-Tuning
- [Fine-Tuning LLMs for Report Summarization (arXiv:2503.10676)](https://arxiv.org/html/2503.10676v1)
- [Is fine-tuning LLMs still worth it in 2025?](https://www.kadoa.com/blog/is-fine-tuning-still-worth-it)
- [LoRA Fine-Tuning On Your Apple Silicon MacBook](https://towardsdatascience.com/lora-fine-tuning-on-your-apple-silicon-macbook-432c7dab614a/)
- [MLX-LM LoRA documentation](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/LORA.md)
- [mlx-tune (Unsloth-compatible API for MLX)](https://github.com/ARahim3/mlx-tune)
- [MeetingBank dataset](https://meetingbank.github.io/)
- [AMI Corpus on Hugging Face](https://huggingface.co/datasets/knkarthick/AMI)
- [DialogSum on Hugging Face](https://huggingface.co/datasets/knkarthick/dialogsum)
- [Efficient Fine-Tuning with LoRA (Databricks)](https://www.databricks.com/blog/efficient-fine-tuning-lora-guide-llms)

### Topic 3: Personalization
- [Tell me what I need to know: LLM-based Personalized Meeting Summarization (arXiv:2410.14545)](https://arxiv.org/html/2410.14545v1)
- [Summaries, Highlights, and Action Items: LLM-powered Meeting Recap System (arXiv:2307.15793)](https://arxiv.org/abs/2307.15793)
- [PLUS: Preference Learning Using Summaries (arXiv:2507.13579)](https://arxiv.org/abs/2507.13579)
- [Prompt Engineering: Build a Summarizer Assistant](https://www.c-sharpcorner.com/article/prompt-engineering-build-a-summarizer-assistant-from-raw-notes-to-crisp-bullet/)
- [LLM Summarization Production Guide (Galileo)](https://galileo.ai/blog/llm-summarization-production-guide)
- [Meetily: Building an Open-Source AI Meeting Assistant](https://www.zackriya.com/meetily-building-an-open-source-ai-powered-meeting-assistant/)
