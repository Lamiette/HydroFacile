(() => {
  const STORAGE_KEY = "hydrofacile_cookie_preferences";
  const STORAGE_VERSION = 1;
  const CONSENT_TTL_MS = 180 * 24 * 60 * 60 * 1000;
  const GA_DISABLE_KEY = "ga-disable-G-QQH5R1ZY11";
  const COOKIE_PATH = "/";
  const OPTIONAL_COOKIE_NAMES = new Set(["_ga", "_gid", "_gat", "_clck", "_clsk", "CLID", "ANONCHK", "MR", "MUID", "SM"]);
  const OPTIONAL_COOKIE_PREFIXES = ["_ga_", "_gat_"];
  const OPTIONAL_STORAGE_PATTERNS = [/^_ga/i, /^_cl/i, /clarity/i];

  const defaultPreferences = () => ({
    necessary: true,
    analytics: false,
  });

  let currentPreferences = defaultPreferences();
  let bannerElement = null;
  let preferencesElement = null;
  let analyticsToggleElement = null;
  let shortcutElement = null;
  let lastFocusedElement = null;

  const normalizePreferences = (preferences) => ({
    necessary: true,
    analytics: Boolean(preferences && preferences.analytics),
  });

  const parseRecord = () => {
    try {
      const rawValue = window.localStorage.getItem(STORAGE_KEY);

      if (!rawValue) {
        return null;
      }

      const parsed = JSON.parse(rawValue);
      const savedAt = Date.parse(parsed.savedAt);

      if (
        !parsed ||
        parsed.version !== STORAGE_VERSION ||
        !Number.isFinite(savedAt) ||
        Date.now() - savedAt > CONSENT_TTL_MS
      ) {
        window.localStorage.removeItem(STORAGE_KEY);
        return null;
      }

      return {
        ...parsed,
        preferences: normalizePreferences(parsed.preferences),
      };
    } catch (error) {
      return null;
    }
  };

  const persistRecord = (preferences, source) => {
    const record = {
      version: STORAGE_VERSION,
      savedAt: new Date().toISOString(),
      source,
      preferences: normalizePreferences(preferences),
    };

    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(record));
    } catch (error) {
      return null;
    }

    return record;
  };

  const shouldClearCookieName = (cookieName) => {
    if (OPTIONAL_COOKIE_NAMES.has(cookieName)) {
      return true;
    }

    return OPTIONAL_COOKIE_PREFIXES.some((prefix) => cookieName.startsWith(prefix));
  };

  const getCookieDomains = () => {
    const hostname = window.location.hostname;

    if (!hostname || hostname === "localhost") {
      return [null];
    }

    const domains = new Set([null, hostname, `.${hostname}`]);
    const parts = hostname.split(".");

    for (let index = 1; index < parts.length - 1; index += 1) {
      domains.add(`.${parts.slice(index).join(".")}`);
    }

    return Array.from(domains);
  };

  const expireCookie = (cookieName, domain) => {
    let cookieValue = `${encodeURIComponent(cookieName)}=; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=0; Path=${COOKIE_PATH}; SameSite=Lax`;

    if (domain) {
      cookieValue += `; Domain=${domain}`;
    }

    if (window.location.protocol === "https:") {
      cookieValue += "; Secure";
    }

    document.cookie = cookieValue;
  };

  const clearOptionalStorage = (storage) => {
    try {
      const keysToRemove = [];

      for (let index = 0; index < storage.length; index += 1) {
        const key = storage.key(index);

        if (key && OPTIONAL_STORAGE_PATTERNS.some((pattern) => pattern.test(key))) {
          keysToRemove.push(key);
        }
      }

      keysToRemove.forEach((key) => storage.removeItem(key));
    } catch (error) {
      return;
    }
  };

  const clearOptionalCookies = () => {
    const cookieNames = document.cookie
      .split(";")
      .map((entry) => entry.trim().split("=")[0])
      .filter(Boolean);

    if (cookieNames.length === 0) {
      clearOptionalStorage(window.localStorage);
      clearOptionalStorage(window.sessionStorage);
      return;
    }

    const domains = getCookieDomains();

    cookieNames.forEach((cookieName) => {
      if (!shouldClearCookieName(cookieName)) {
        return;
      }

      domains.forEach((domain) => expireCookie(cookieName, domain));
    });

    clearOptionalStorage(window.localStorage);
    clearOptionalStorage(window.sessionStorage);
  };

  const setGaDisabledState = (analyticsGranted) => {
    window[GA_DISABLE_KEY] = !analyticsGranted;
  };

  const activateDeferredScripts = () => {
    const deferredScripts = document.querySelectorAll('script[type="text/plain"][data-consent-category]');

    deferredScripts.forEach((placeholder) => {
      const category = placeholder.dataset.consentCategory;

      if (!currentPreferences[category] || placeholder.dataset.consentExecuted === "true") {
        return;
      }

      const executable = document.createElement("script");
      const externalSource = placeholder.dataset.consentSrc;

      Array.from(placeholder.attributes).forEach((attribute) => {
        if (attribute.name === "type" || attribute.name.startsWith("data-consent")) {
          return;
        }

        executable.setAttribute(attribute.name, attribute.value);
      });

      if (externalSource) {
        executable.src = externalSource;
        executable.async = true;
      } else {
        executable.text = placeholder.textContent || "";
      }

      placeholder.dataset.consentExecuted = "true";
      placeholder.parentNode.insertBefore(executable, placeholder.nextSibling);
    });
  };

  const updateBodyState = ({ bannerVisible = false } = {}) => {
    document.body.classList.toggle("cookie-consent-banner-visible", bannerVisible);

    if (shortcutElement) {
      shortcutElement.hidden = true;
    }
  };

  const applyPreferences = (preferences) => {
    currentPreferences = normalizePreferences(preferences);
    setGaDisabledState(currentPreferences.analytics);
    document.documentElement.dataset.cookieAnalytics = currentPreferences.analytics ? "granted" : "denied";

    if (!currentPreferences.analytics) {
      clearOptionalCookies();
    } else {
      activateDeferredScripts();
    }

    document.dispatchEvent(
      new CustomEvent("hydrofacile:cookie-consent-changed", {
        detail: { ...currentPreferences },
      }),
    );
  };

  const closePreferences = () => {
    preferencesElement.hidden = true;
    document.body.classList.remove("cookie-preferences-open");

    if (lastFocusedElement && typeof lastFocusedElement.focus === "function") {
      lastFocusedElement.focus();
    }
  };

  const openPreferences = () => {
    lastFocusedElement = document.activeElement;
    analyticsToggleElement.checked = currentPreferences.analytics;
    preferencesElement.hidden = false;
    document.body.classList.add("cookie-preferences-open");
    preferencesElement.querySelector(".cookie-preferences__close").focus();
  };

  const savePreferences = (preferences, source) => {
    const previousAnalyticsState = currentPreferences.analytics;
    const normalizedPreferences = normalizePreferences(preferences);

    persistRecord(normalizedPreferences, source);
    applyPreferences(normalizedPreferences);
    bannerElement.hidden = true;

    if (shortcutElement) {
      shortcutElement.remove();
      shortcutElement = null;
    }

    updateBodyState({ bannerVisible: false });
    closePreferences();

    if (previousAnalyticsState && !normalizedPreferences.analytics) {
      window.location.reload();
    }
  };

  const handleAction = (action) => {
    switch (action) {
      case "accept":
        savePreferences({ analytics: true }, "accept-all");
        break;
      case "reject":
        savePreferences({ analytics: false }, "reject-all");
        break;
      case "customize":
        openPreferences();
        break;
      case "save":
        savePreferences({ analytics: analyticsToggleElement.checked }, "custom");
        break;
      default:
        break;
    }
  };

  const buildUi = () => {
    document.body.insertAdjacentHTML(
      "beforeend",
      `
        <div class="cookie-consent" data-cookie-banner hidden>
          <section class="cookie-consent__panel" aria-labelledby="cookie-consent-title" aria-describedby="cookie-consent-description" role="dialog">
            <p class="cookie-consent__eyebrow">Cookies</p>
            <h2 class="cookie-consent__title" id="cookie-consent-title">Choisir les cookies</h2>
            <p class="cookie-consent__description" id="cookie-consent-description">
              HydroFacile utilise uniquement les traceurs n&eacute;cessaires au fonctionnement du site par d&eacute;faut. Avec votre accord, nous activons aussi Google Analytics et Microsoft Clarity pour mesurer l&apos;audience et am&eacute;liorer les contenus.
            </p>
            <div class="cookie-consent__actions">
              <button class="cookie-consent__button cookie-consent__button--reject" data-cookie-action="reject" type="button">Tout refuser</button>
              <button class="cookie-consent__button cookie-consent__button--accept" data-cookie-action="accept" type="button">Tout accepter</button>
              <button class="cookie-consent__button cookie-consent__button--neutral" data-cookie-action="customize" type="button">Personnaliser</button>
            </div>
            <p class="cookie-consent__meta">
              Votre choix est m&eacute;moris&eacute; pendant 6 mois et peut &ecirc;tre modifi&eacute; &agrave; tout moment.
              <a href="/politique-confidentialite/">En savoir plus</a>
            </p>
          </section>
        </div>
        <div class="cookie-preferences" data-cookie-preferences hidden>
          <div class="cookie-preferences__backdrop" data-cookie-close></div>
          <section class="cookie-preferences__dialog" aria-labelledby="cookie-preferences-title" aria-describedby="cookie-preferences-description" aria-modal="true" role="dialog">
            <div class="cookie-preferences__header">
              <div>
                <p class="cookie-consent__eyebrow">Pr&eacute;f&eacute;rences</p>
                <h2 class="cookie-preferences__title" id="cookie-preferences-title">G&eacute;rer les cookies</h2>
              </div>
              <button class="cookie-preferences__close" data-cookie-close type="button" aria-label="Fermer la fen&ecirc;tre des cookies">&times;</button>
            </div>
            <p class="cookie-preferences__description" id="cookie-preferences-description">
              Les cookies strictement n&eacute;cessaires restent actifs. Les outils de mesure d&apos;audience restent d&eacute;sactiv&eacute;s tant que vous ne les avez pas autoris&eacute;s.
            </p>
            <div class="cookie-preferences__list">
              <div class="cookie-preferences__item">
                <div>
                  <strong>Cookies n&eacute;cessaires</strong>
                  <p>Ils permettent le fonctionnement normal du site et la m&eacute;morisation de votre choix en mati&egrave;re de consentement.</p>
                </div>
                <span class="cookie-preferences__tag">Toujours actifs</span>
              </div>
              <label class="cookie-preferences__item cookie-preferences__item--toggle" for="cookie-analytics-toggle">
                <div>
                  <strong>Mesure d&apos;audience</strong>
                  <p>Google Analytics et Microsoft Clarity, activ&eacute;s uniquement avec votre accord pr&eacute;alable.</p>
                </div>
                <span class="cookie-toggle">
                  <input id="cookie-analytics-toggle" name="cookie-analytics-toggle" type="checkbox">
                  <span class="cookie-toggle__track" aria-hidden="true"></span>
                </span>
              </label>
            </div>
            <div class="cookie-consent__actions">
              <button class="cookie-consent__button cookie-consent__button--reject" data-cookie-action="reject" type="button">Tout refuser</button>
              <button class="cookie-consent__button cookie-consent__button--accept" data-cookie-action="accept" type="button">Tout accepter</button>
              <button class="cookie-consent__button cookie-consent__button--neutral" data-cookie-action="save" type="button">Enregistrer mes choix</button>
            </div>
          </section>
        </div>
        <button class="cookie-consent-shortcut" data-cookie-shortcut type="button" hidden>Cookies</button>
      `,
    );

    bannerElement = document.querySelector("[data-cookie-banner]");
    preferencesElement = document.querySelector("[data-cookie-preferences]");
    analyticsToggleElement = document.getElementById("cookie-analytics-toggle");
    shortcutElement = document.querySelector("[data-cookie-shortcut]");

    bannerElement.addEventListener("click", (event) => {
      const target = event.target.closest("[data-cookie-action]");

      if (!target) {
        return;
      }

      handleAction(target.dataset.cookieAction);
    });

    preferencesElement.addEventListener("click", (event) => {
      const actionTarget = event.target.closest("[data-cookie-action]");

      if (actionTarget) {
        handleAction(actionTarget.dataset.cookieAction);
        return;
      }

      if (event.target.closest("[data-cookie-close]")) {
        closePreferences();
      }
    });

    shortcutElement.addEventListener("click", () => {
      openPreferences();
    });

    document.addEventListener("click", (event) => {
      const openPreferencesTrigger = event.target.closest("[data-open-cookie-preferences]");

      if (!openPreferencesTrigger) {
        return;
      }

      event.preventDefault();
      openPreferences();
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && !preferencesElement.hidden) {
        closePreferences();
      }
    });
  };

  const injectFooterLink = () => {
    const legalFooter = document.querySelector(".footer-legal");

    if (!legalFooter || legalFooter.querySelector(".cookie-consent-footer-link")) {
      return;
    }

    legalFooter.insertAdjacentHTML(
      "beforeend",
      ' <button class="muted-link cookie-consent-footer-link" type="button" data-open-cookie-preferences>G&eacute;rer les cookies</button>',
    );
  };

  const init = () => {
    buildUi();
    injectFooterLink();

    const record = parseRecord();

    if (!record) {
      applyPreferences(defaultPreferences());
      bannerElement.hidden = false;
      updateBodyState({ bannerVisible: true });
      return;
    }

    applyPreferences(record.preferences);
    bannerElement.hidden = true;

    if (shortcutElement) {
      shortcutElement.remove();
      shortcutElement = null;
    }

    updateBodyState({ bannerVisible: false });
  };

  window.HydroFacileCookieConsent = {
    openPreferences,
    getPreferences: () => ({ ...currentPreferences }),
  };

  init();
})();
