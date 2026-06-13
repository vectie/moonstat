const steps = [
  {
    id: 1,
    label: "基础信息",
    detail: "填写姓名、邮箱与机构",
  },
  {
    id: 2,
    label: "赛道与材料",
    detail: "选赛道并补齐作品资料",
  },
  {
    id: 3,
    label: "确认提交",
    detail: "同意协议并完成报名",
  },
];

const trackMeta = {
  academic: "🎓 学术龙虾 · 做科研的最强搭档",
  productivity: "⚡ 生产力龙虾 · 一人成军的效率引擎",
  life: "🏠 生活龙虾 · 把日子过好",
};

const form = document.getElementById("register-form");
const trackGrid = document.getElementById("track-grid");
const trackInput = document.getElementById("track-input");
const progressPanel = document.getElementById("progress-panel");
const progressMobile = document.getElementById("progress-mobile");
const progressCopy = document.getElementById("progress-copy");
const errorNode = document.getElementById("form-error");
const submitButton = document.getElementById("submit-button");
const agree = document.getElementById("agree");
const termsDialog = document.getElementById("terms-dialog");
const termsBackdrop = document.getElementById("terms-backdrop");
const openTerms = document.getElementById("open-terms");
const closeTerms = document.getElementById("close-terms");
const pageMain = document.querySelector(".page-main");
const successTemplate = document.getElementById("success-template");

function computeStep() {
  const data = new FormData(form);
  const hasBasics =
    data.get("fullName")?.trim() &&
    data.get("email")?.trim() &&
    data.get("organization")?.trim();
  const hasProject =
    data.get("track")?.trim() &&
    data.get("projectTitle")?.trim() &&
    data.get("projectDescription")?.trim() &&
    data.get("pdfUrl")?.trim() &&
    data.get("videoUrl")?.trim() &&
    data.get("posterUrl")?.trim();

  if (!hasBasics) return 1;
  if (!hasProject) return 2;
  return 3;
}

function progressText(step) {
  if (step === 1) return "先填写姓名、邮箱与机构";
  if (step === 2) return "基础信息已完成，继续选择赛道并补齐材料";
  return "资料已经就绪，确认协议后即可提交";
}

function renderProgress() {
  const current = computeStep();
  progressCopy.textContent = progressText(current);

  progressPanel.innerHTML = steps
    .map((step, index) => {
      const done = current > step.id;
      const currentStep = current === step.id;
      const line = index < steps.length - 1;
      return `
        <div class="step">
          <div class="step-rail">
            <div class="step-node ${done ? "is-done" : ""} ${currentStep ? "is-current" : ""}">
              ${done ? "✓" : step.id}
            </div>
            ${line ? `<div class="step-line ${done ? "is-done" : ""}"></div>` : ""}
          </div>
          <div class="step-copy">
            <small>${currentStep ? "当前步骤" : done ? "已完成" : `步骤 ${step.id}`}</small>
            <strong>${step.label}</strong>
            <p>${step.detail}</p>
          </div>
        </div>
      `;
    })
    .join("");

  progressMobile.innerHTML = steps
    .map((step) => {
      const done = current > step.id;
      const currentStep = current === step.id;
      return `<div class="progress-chip ${done ? "is-done" : ""} ${currentStep ? "is-current" : ""}">
        ${done ? "✓" : step.id}. ${step.label}
      </div>`;
    })
    .join("");
}

function selectTrack(trackId) {
  trackInput.value = trackId;
  for (const card of trackGrid.querySelectorAll(".track-card")) {
    card.classList.toggle("is-selected", card.dataset.track === trackId);
  }
  renderProgress();
}

function validUrl(value, required) {
  const trimmed = value.trim();
  if (!trimmed) return !required;
  try {
    const url = new URL(trimmed);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch (_) {
    return false;
  }
}

function showError(message) {
  errorNode.hidden = false;
  errorNode.textContent = message;
}

function clearError() {
  errorNode.hidden = true;
  errorNode.textContent = "";
}

function setInvalidState(name, invalid) {
  const field = form.querySelector(`[name="${name}"]`)?.closest(".field");
  if (field) field.classList.toggle("is-invalid", invalid);
}

function validateForm() {
  clearError();

  const requiredUrls = ["pdfUrl", "videoUrl", "posterUrl"];
  const optionalUrls = ["repoUrl"];
  let invalid = false;

  for (const name of requiredUrls) {
    const input = form.elements[name];
    const ok = validUrl(input.value, true);
    setInvalidState(name, !ok);
    invalid = invalid || !ok;
  }

  for (const name of optionalUrls) {
    const input = form.elements[name];
    const ok = validUrl(input.value, false);
    setInvalidState(name, !ok);
    invalid = invalid || !ok;
  }

  if (!trackInput.value) {
    showError("请选择一个参赛赛道。");
    return false;
  }

  if (invalid) {
    showError("请确保所有链接都可以正常访问后再提交。");
    return false;
  }

  if (!agree.checked) {
    showError("请先勾选同意参赛协议。");
    return false;
  }

  return true;
}

function openTermsDialog() {
  termsBackdrop.hidden = false;
  termsDialog.showModal();
}

function closeTermsDialog() {
  termsBackdrop.hidden = true;
  termsDialog.close();
}

function showSuccess() {
  const success = successTemplate.content.firstElementChild.cloneNode(true);
  success.querySelector("#success-track").textContent =
    trackMeta[trackInput.value] ?? "";
  success.querySelector("#restart-button").addEventListener("click", () => {
    success.remove();
    pageMain.hidden = false;
    window.scrollTo({ top: 0, behavior: "smooth" });
  });
  pageMain.hidden = true;
  document.body.appendChild(success);
  window.scrollTo({ top: 0, behavior: "smooth" });
}

trackGrid.addEventListener("click", (event) => {
  const card = event.target.closest(".track-card");
  if (!card) return;
  selectTrack(card.dataset.track);
});

form.addEventListener("input", () => {
  clearError();
  renderProgress();
});

form.addEventListener("submit", (event) => {
  event.preventDefault();
  submitButton.disabled = true;
  submitButton.textContent = "提交中…";

  const ok = validateForm() && form.reportValidity();
  if (ok) {
    window.setTimeout(() => {
      showSuccess();
      submitButton.disabled = false;
      submitButton.textContent = "提交参赛作品";
    }, 450);
    return;
  }

  submitButton.disabled = false;
  submitButton.textContent = "提交参赛作品";
});

openTerms.addEventListener("click", openTermsDialog);
closeTerms.addEventListener("click", closeTermsDialog);
termsBackdrop.addEventListener("click", closeTermsDialog);
termsDialog.addEventListener("click", (event) => {
  const rect = termsDialog.getBoundingClientRect();
  const inside =
    rect.top <= event.clientY &&
    event.clientY <= rect.top + rect.height &&
    rect.left <= event.clientX &&
    event.clientX <= rect.left + rect.width;
  if (!inside) closeTermsDialog();
});

renderProgress();
