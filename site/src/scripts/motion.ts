// Scroll-triggered motion on the landing page. Each piece plays once, when
// it is first seen:
//
// - section markers: the corner dots, then the shape (.marker in global.css);
// - the desk picture: the screen recording plays while it is on screen
//   (Desk.astro);
// - the sky picture: the widgets rise in, then drift while the page scrolls
//   (Sky.astro);
// - the price: the days switch on, then the price is struck (Price.astro).
//
// The page is complete without this script. Only things that are below the
// fold at load are hidden first (`data-wait`), so nothing visible ever blinks
// out. With prefers-reduced-motion the CSS turns every move into a plain
// fade or nothing at all, and the price and the drift are skipped here.

const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

/** Still below the first screen? */
function below(el: Element): boolean {
  return el.getBoundingClientRect().top > window.innerHeight * 0.9;
}

/** Calls back once, the first time `threshold` of the element is on screen. */
function whenSeen(el: Element, threshold: number, callback: () => void): void {
  const observer = new IntersectionObserver(
    (entries) => {
      if (!entries.some((entry) => entry.isIntersecting)) return;
      observer.disconnect();
      callback();
    },
    { threshold },
  );
  observer.observe(el);
}

function initMarkers(): void {
  document.querySelectorAll<HTMLElement>('.marker:not(.play)').forEach((marker) => {
    if (!below(marker)) return;
    marker.dataset.wait = '';
    whenSeen(marker, 1, () => {
      delete marker.dataset.wait;
      marker.classList.add('play');
    });
  });
}

function initDesk(): void {
  const video = document.querySelector<HTMLVideoElement>('#desk-video');
  if (!video) return;

  // Plays only while at least a third of it is on screen, the tab is visible
  // and the visitor has not asked for less motion.
  let onscreen = false;
  const sync = () => {
    if (onscreen && !document.hidden && !reducedMotion.matches) {
      // Autoplay can be refused (e.g. Low Power Mode); the still stays then.
      video.play().catch(() => {});
    } else {
      video.pause();
    }
  };
  new IntersectionObserver(
    (entries) => {
      onscreen = entries[entries.length - 1].isIntersecting;
      sync();
    },
    { threshold: 0.35 },
  ).observe(video);
  document.addEventListener('visibilitychange', sync);
  reducedMotion.addEventListener('change', sync);
}

function initSky(): void {
  const sky = document.getElementById('sky');
  if (!sky) return;

  if (below(sky)) {
    sky.dataset.wait = '';
    whenSeen(sky, 0.2, () => delete sky.dataset.wait);
  }

  // Drift: --p runs from -1 (the picture is just below the viewport) to 1
  // (just above it); each widget multiplies it by its own distance.
  let onscreen = false;
  let queued = false;
  const update = () => {
    queued = false;
    if (reducedMotion.matches) {
      sky.style.removeProperty('--p');
      return;
    }
    const rect = sky.getBoundingClientRect();
    const range = (window.innerHeight + rect.height) / 2;
    const offset = rect.top + rect.height / 2 - window.innerHeight / 2;
    const p = Math.max(-1, Math.min(1, -offset / range));
    sky.style.setProperty('--p', p.toFixed(3));
  };
  const request = () => {
    if (!onscreen || queued) return;
    queued = true;
    requestAnimationFrame(update);
  };
  new IntersectionObserver((entries) => {
    onscreen = entries[entries.length - 1].isIntersecting;
    request();
  }).observe(sky);
  window.addEventListener('scroll', request, { passive: true });
  window.addEventListener('resize', request);
  reducedMotion.addEventListener('change', update);
}

function initPrice(): void {
  const plan = document.getElementById('plan');
  const now = plan?.querySelector<HTMLElement>('.band__now');
  if (!plan || !now || reducedMotion.matches || !below(plan)) return;

  // Where the regular price stands before it is struck: in the launch
  // price's place, i.e. shifted left by that price's width and the gap.
  const setShift = () => {
    const gap = parseFloat(getComputedStyle(now.parentElement!).columnGap) || 0;
    plan.style.setProperty('--shift', `${-(now.offsetWidth + gap)}px`);
  };
  setShift();
  // The web font may arrive after this ran and change the width.
  void document.fonts?.ready.then(setShift);

  plan.dataset.wait = '';
  whenSeen(plan.querySelector('.band') ?? plan, 1, () => delete plan.dataset.wait);
}

export function initMotion(): void {
  if (!('IntersectionObserver' in window)) return;
  initMarkers();
  initDesk();
  initSky();
  initPrice();
}
