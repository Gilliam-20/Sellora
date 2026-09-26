// ISO 3166-1 alpha-2 codes for EU member states. Mapped to the "eu" region
// with EUR pricing regardless of whether that member actually circulates
// EUR (e.g. Bulgaria) - this is a shipping/pricing region, not a currency
// union membership check.
const EU_MEMBER_COUNTRY_CODES = [
  "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR",
  "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK",
  "SI", "ES", "SE",
];

const REGION_CONFIG = Object.freeze({
  KE: Object.freeze({ region: "kenya", currency: "KES" }),
  US: Object.freeze({ region: "us", currency: "USD" }),
  GB: Object.freeze({ region: "uk", currency: "GBP" }),
  ...Object.fromEntries(
      EU_MEMBER_COUNTRY_CODES.map(
          (code) => [code, Object.freeze({ region: "eu", currency: "EUR" })],
      ),
  ),
});

const FALLBACK_REGION = Object.freeze({ region: "us", currency: "USD" });

/**
 * @param {string} countryCode ISO 3166-1 alpha-2 country code.
 * @return {{region: string, currency: string}} The region/currency for
 *   that country, or the `us`/`USD` fallback if unrecognized.
 */
function resolveRegion(countryCode) {
  const code = String(countryCode || "").trim().toUpperCase();
  return REGION_CONFIG[code] || FALLBACK_REGION;
}

export { REGION_CONFIG, resolveRegion };
