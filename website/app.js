function createBoard(board) {
  const text = board.dataset.board || "";
  const characters = Array.from(text.padEnd(text.length, " "));
  board.textContent = "";

  characters.forEach((character, index) => {
    const flap = document.createElement("span");
    flap.className = "flap";
    flap.dataset.index = String(index);

    const inner = document.createElement("span");
    inner.textContent = character;
    flap.append(inner);
    board.append(flap);
  });
}

document.querySelectorAll("[data-board]").forEach(createBoard);

const heroFlaps = Array.from(document.querySelectorAll(".board-frame .flap"));
let tick = 0;

function animateHeroBoard() {
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  const flap = heroFlaps[tick % heroFlaps.length];
  if (!flap) return;

  flap.classList.remove("is-flipping");
  void flap.offsetWidth;
  flap.classList.add("is-flipping");
  tick += 1;
}

window.setInterval(animateHeroBoard, 680);
