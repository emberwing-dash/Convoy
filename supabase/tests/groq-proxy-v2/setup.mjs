globalThis.Deno = { env: { get: (k) => ({ GROQ_API_KEY_1: "x" })[k] }, serve: () => {} };
