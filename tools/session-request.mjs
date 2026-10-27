import { request } from 'playwright';

// Use the same cookie semantics as the captured Playwright storage state.
export async function sessionRequest(url, state, options = {}) {
  const context = await request.newContext({ storageState: state, timeout: 20_000 });
  try {
    const result = await context.fetch(url, {
      method: options.method ?? 'GET', headers: options.headers, data: options.body,
      maxRedirects: 0, maxRetries: 0,
    });
    state.cookies = (await context.storageState()).cookies;
    const status = result.status();
    return new Response([204, 205, 304].includes(status) ? null : await result.body(), {
      status, headers: result.headersArray().map(({ name, value }) => [name, value]),
    });
  } finally { await context.dispose(); }
}
