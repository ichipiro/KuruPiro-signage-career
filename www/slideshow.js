const MANIFEST_URL = './drive-images/index.json';
const MANIFEST_REFRESH_INTERVAL = 60 * 1000;
const IMAGE_ROTATE_INTERVAL = 10 * 1000;

let images = [];
let imageIndex = 0;
let manifestVersion = '';
let rotateTimer = null;
let completedCycles = 0;
let cycleCompleteHold = false;
let progressTimer = null;
let cycleStartedAt = 0;

function updateTitle() {
  if (images.length === 0) {
    document.title = 'くるぴろスライドショー [0/0] cycle=0';
    return;
  }

  if (cycleCompleteHold) {
    document.title = `くるぴろスライドショー [${images.length}/${images.length}] cycle=${completedCycles}`;
    return;
  }

  document.title = `くるぴろスライドショー [${imageIndex + 1}/${images.length}] cycle=${completedCycles}`;
}

function updateSlide() {
  const imageEl = document.getElementById('slideshow-image');
  const progressEl = document.getElementById('slideshow-progress');
  if (!imageEl) return;

  if (images.length === 0) {
    imageEl.removeAttribute('src');
    imageEl.style.visibility = 'hidden';
    if (progressEl) {
      progressEl.style.visibility = 'hidden';
    }
    updateTitle();
    return;
  }

  const current = images[imageIndex % images.length];
  imageEl.style.visibility = 'visible';
  if (progressEl) {
    progressEl.style.visibility = 'visible';
  }
  imageEl.src = current.path;
  updateTitle();
}

function updateProgress() {
  const progressFillEl = document.getElementById('slideshow-progress-fill');
  if (!progressFillEl) return;

  if (images.length === 0) {
    progressFillEl.style.width = '0%';
    return;
  }

  const totalCycleMs = images.length * IMAGE_ROTATE_INTERVAL;
  if (totalCycleMs <= 0) {
    progressFillEl.style.width = '0%';
    return;
  }

  const elapsedMs = cycleCompleteHold ? totalCycleMs : Math.max(0, Date.now() - cycleStartedAt);
  const progress = Math.min(elapsedMs / totalCycleMs, 1);
  progressFillEl.style.width = `${progress * 100}%`;
}

function stopTimers() {
  if (rotateTimer) {
    clearInterval(rotateTimer);
    rotateTimer = null;
  }
  if (progressTimer) {
    clearInterval(progressTimer);
    progressTimer = null;
  }
}

function startCycle() {
  stopTimers();

  imageIndex = 0;
  completedCycles = 0;
  cycleCompleteHold = false;

  cycleStartedAt = Date.now();

  updateSlide();
  updateProgress();

  progressTimer = setInterval(updateProgress, 200);

  if (images.length <= 1) {
    rotateTimer = setInterval(() => {
      completedCycles = 1;
      cycleCompleteHold = true;
      updateTitle();
      updateProgress();
      clearInterval(rotateTimer);
      rotateTimer = null;
    }, IMAGE_ROTATE_INTERVAL);
    return;
  }

  rotateTimer = setInterval(() => {
    const nextIndex = (imageIndex + 1) % images.length;
    if (nextIndex === 0) {
      completedCycles += 1;
      cycleCompleteHold = true;
      clearInterval(rotateTimer);
      rotateTimer = null;
      updateTitle();
      updateProgress();
      return;
    }
    imageIndex = nextIndex;
    updateSlide();
  }, IMAGE_ROTATE_INTERVAL);
}

async function loadManifest() {
  try {
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

    if (nextVersion === manifestVersion) {
      if (document.visibilityState === 'visible' && cycleCompleteHold) {
        startCycle();
      }
      return;
    }

    manifestVersion = nextVersion;
    images = nextImages.filter((image) => typeof image.path === 'string' && image.path.length > 0);
    startCycle();
  } catch (error) {
    if (images.length === 0) {
      stopTimers();
      updateSlide();
    }
  }
}

document.addEventListener('DOMContentLoaded', () => {
  updateSlide();
  loadManifest();
  setInterval(loadManifest, MANIFEST_REFRESH_INTERVAL);
});

document.addEventListener('visibilitychange', () => {
  if (document.visibilityState !== 'visible') {
    return;
  }

  if (images.length > 0) {
    startCycle();
  } else {
    loadManifest();
  }
});
