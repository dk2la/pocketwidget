// Redirects www.pocketwidget.tech to pocketwidget.tech, keeping the path and
// the query. The site Worker serves static assets only and cannot tell hosts
// apart, so the redirect lives in this separate Worker.
export default {
  fetch(request) {
    const url = new URL(request.url);
    url.hostname = 'pocketwidget.tech';
    return Response.redirect(url.href, 301);
  },
};
