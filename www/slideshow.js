const MANIFEST_URL = './drive-images/index.json';
const MANIFEST_REFRESH_INTERVAL = 60 * 1000;
const IMAGE_ROTATE_INTERVAL = 10 * 1000;

let images = [];
let imageIndex = 0;
let manifestVersion = '';
let rotateTimer = null;
let completedCycles = 0;

function updateTitle() {
  if (images.length === 0) {
    document.title = 'くるぴろスライドショー [0/0] cycle=0';
    return;
  }

  document.title = `くるぴろスライドショー [${imageIndex + 1}/${images.length}] cycle=${completedCycles}`;
}

function updateSlide() {
  const imageEl = document.getElementById('slideshow-image');
  if (!imageEl) return;

  if (images.length === 0) {
    imageEl.removeAttribute('src');
    imageEl.style.visibility = 'hidden';
    updateTitle();
    return;
  }

  const current = images[imageIndex % images.length];
  imageEl.style.visibility = 'visible';
  imageEl.src = current.path;
  updateTitle();
}

function resetRotation() {
  if (rotateTimer) {
    clearInterval(rotateTimer);
    rotateTimer = null;
  }

  updateSlide();

  if (images.length <= 1) {
    return;
  }

  rotateTimer = setInterval(() => {
    const nextIndex = (imageIndex + 1) % images.length;
    if (nextIndex === 0) {
      completedCycles += 1;
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
      return;
    }

    manifestVersion = nextVersion;
    images = nextImages.filter((image) => typeof image.path === 'string' && image.path.length > 0);
    imageIndex = 0;
    completedCycles = 0;
    resetRotation();
  } catch (error) {
    if (images.length === 0) {
      updateSlide();
    }
  }
}

document.addEventListener('DOMContentLoaded', () => {
  updateSlide();
  loadManifest();
  setInterval(loadManifest, MANIFEST_REFRESH_INTERVAL);
});
