// /sitemap.xml: the pages search engines should index. The thanks page and
// the 404 page are left out on purpose. Add a path here when a page is added.
import type { APIRoute } from 'astro';
import { siteOrigin } from '../config';

const paths = ['/', '/trust', '/terms', '/privacy', '/refund'];

export const GET: APIRoute = ({ site }) => {
  const origin = site ?? new URL(siteOrigin);
  const urls = paths
    .map((path) => `  <url><loc>${new URL(path, origin).href}</loc></url>`)
    .join('\n');
  const body = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls}
</urlset>
`;
  return new Response(body, { headers: { 'Content-Type': 'application/xml; charset=utf-8' } });
};
