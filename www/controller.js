const DEFAULT_MAIN_URL = '/';
const DEFAULT_MAIN_DURATION_MS = 60 * 1000;
const DEFAULT_IMAGE_DURATION_MS = 10 * 1000;
const MANIFEST_URL = './drive-images/index.json';

let manifestVersion = '';
let images = [];
let activeTimers = [];
let progressTimer = null;

function getQueryConfig() {
  const params = new URLSearchParams(window.location.search);
  const mainUrl = params.get('main') || DEFAULT_MAIN_URL;
  const mainDurationMs = Number(params.get('mainDurationMs')) || DEFAULT_MAIN_DURATION_MS;
  const imageDurationMs = Number(params.get('imageDurationMs')) || DEFAULT_IMAGE_DURATION_MS;
  return { mainUrl, mainDurationMs, imageDurationMs };
}

function clearActiveTimers() {
  activeTimers.forEach((timerId) => clearTimeout(timerId));
  activeTimers = [];
  if (progressTimer) {
    clearInterval(progressTimer);
    progressTimer = null;
  }
}

function scheduleTimeout(callback, delayMs) {
  const timerId = setTimeout(callback, delayMs);
  activeTimers.push(timerId);
}

async function loadImages() {
  const response = await fetch(`${MANIFEST_URL}?t=${Date.now()}`, {
    cache: 'no-store'
  });
  if (!response.ok) {
    throw new Error(`manifest fetch failed: ${response.status}`);
  }

  const manifest = await response.json();
  const nextImages = Array.isArray(manifest.images) ? manifest.images : [];
  const nextVersion = JSON.stringify({
    updatedAt: manifest.updatedAt || null,
    images: nextImages.map((image) => image.path)
  });

  manifestVersion = nextVersion;
  images = nextImages.filter((image) => typeof image.path === 'string' && image.path.length > 0);
}

function updateProgress(startedAt, totalDurationMs) {
  const progressFillEl = document.getElementById('ad-progress-fill');
  if (!progressFillEl) return;

  const elapsedMs = Math.max(0, Date.now() - startedAt);
  const progress = totalDurationMs <= 0 ? 1 : Math.min(elapsedMs / totalDurationMs, 1);
  progressFillEl.style.width = `${progress * 100}%`;
}

function showMain(config) {
  clearActiveTimers();

  const frameEl = document.getElementById('signage-frame');
  const adLayerEl = document.getElementById('ad-layer');
  const progressFillEl = document.getElementById('ad-progress-fill');

  if (frameEl && frameEl.src !== config.mainUrl) {
    frameEl.src = config.mainUrl;
  }
  if (adLayerEl) {
    adLayerEl.classList.add('hidden');
  }
  if (progressFillEl) {
    progressFillEl.style.width = '0%';
  }

  scheduleTimeout(async () => {
    try {
      await loadImages();
    } catch (error) {
      images = [];
    }

    if (images.length === 0) {
      showMain(config);
      return;
    }

    showAds(config);
  }, config.mainDurationMs);
}

function showAds(config) {
  clearActiveTimers();

  const adLayerEl = document.getElementById('ad-layer');
  const adImageEl = document.getElementById('ad-image');
  if (!adLayerEl || !adImageEl || images.length === 0) {
    showMain(config);
    return;
  }

  adLayerEl.classList.remove('hidden');
  adImageEl.src = images[0].path;

  const startedAt = Date.now();
  const totalDurationMs = images.length * config.imageDurationMs;
  updateProgress(startedAt, totalDurationMs);
  progressTimer = setInterval(() => updateProgress(startedAt, totalDurationMs), 200);

  for (let index = 1; index < images.length; index += 1) {
    scheduleTimeout(() => {
      adImageEl.src = images[index].path;
    }, index * config.imageDurationMs);
  }

  scheduleTimeout(() => {
    showMain(config);
  }, totalDurationMs);
}

document.addEventListener('DOMContentLoaded', async () => {
  const config = getQueryConfig();
  showMain(config);
});
