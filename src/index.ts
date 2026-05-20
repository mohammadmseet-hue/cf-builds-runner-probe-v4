export default {
  async fetch(request: Request): Promise<Response> {
    return new Response('Workers Builds probe worker - alive', { status: 200 });
  }
};
