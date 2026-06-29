const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");

admin.initializeApp();

const geminiApiKey = defineSecret("GEMINI_API_KEY");

const preferredModels = [
  "gemini-2.0-flash",
  "gemini-2.5-flash",
  "gemini-2.5-flash-lite",
  "gemini-1.5-flash",
  "gemini-3-flash-preview",
];

const prompt = `
You are KasiAI, an agricultural crop disease assistant for Cambodian farmers.
Analyze this crop image automatically. The user will not choose crop type.
Return ONLY valid JSON. Do not use markdown.

Rules:
- Detect the crop type from the image.
- Detect the most likely disease or healthy status.
- If the image is not a crop/plant image or is unclear, say it cannot be determined.
- Give practical advice in Khmer.
- Do not claim 100% certainty.
- Do not recommend dangerous chemical use without expert consultation.
- Keep the Khmer text clear and useful for Cambodian farmers.

JSON format:
{
  "crop_kh": "ឈ្មោះដំណាំជាភាសាខ្មែរ",
  "crop_en": "Crop name in English",
  "disease_kh": "ឈ្មោះជំងឺជាភាសាខ្មែរ ឬ សុខភាពល្អ",
  "disease_en": "Disease name in English or Healthy",
  "severity_kh": "ស្រាល / មធ្យម / ធ្ងន់ / មិនច្បាស់",
  "confidence": "ខ្ពស់ / មធ្យម / ទាប",
  "symptoms_kh": "ពណ៌នារោគសញ្ញាដែលមើលឃើញ",
  "treatment_kh": [
    "វិធីព្យាបាលទី១",
    "វិធីព្យាបាលទី២",
    "វិធីព្យាបាលទី៣"
  ],
  "prevention_kh": [
    "វិធីការពារទី១",
    "វិធីការពារទី២"
  ],
  "warning_kh": "ការព្រមានសុវត្ថិភាព"
}
`;

exports.analyzeCropImage = onCall(
  {
    region: "asia-southeast1",
    timeoutSeconds: 120,
    memory: "1GiB",
    invoker: "public",
    secrets: [geminiApiKey],
  },
  async (request) => {
    // Public callable for demo/student project.
    // Gemini API key stays protected in Firebase Secret Manager, not inside Flutter app.
    const data = request.data || {};
    const imageBase64 = typeof data.imageBase64 === "string" ? data.imageBase64.trim() : "";
    const mimeType = typeof data.mimeType === "string" ? data.mimeType.trim() : "image/jpeg";

    if (!imageBase64) {
      throw new HttpsError("invalid-argument", "មិនមានរូបភាពសម្រាប់វិភាគទេ។");
    }

    const key = geminiApiKey.value();
    if (!key) {
      throw new HttpsError("failed-precondition", "GEMINI_API_KEY secret មិនទាន់បានកំណត់ក្នុង Firebase Functions ទេ។");
    }

    const models = await getModelsToTry(key);
    let lastError = null;

    for (const model of models) {
      try {
        return await callGenerateContent({ model, apiKey: key, imageBase64, mimeType });
      } catch (error) {
        lastError = error;
        const message = String(error && error.message ? error.message : error);
        if (message.includes("401") || message.includes("403") || message.toLowerCase().includes("api key")) {
          throw new HttpsError("permission-denied", "Gemini API key មិនត្រឹមត្រូវ ត្រូវបានបិទ ឬ Project មិនមានសិទ្ធិប្រើ API។");
        }
      }
    }

    throw new HttpsError("internal", lastError ? String(lastError.message || lastError) : "AI មិនអាចវិភាគបានទេ។");
  }
);


exports.analyzeCropImageHttp = onRequest(
  {
    region: "asia-southeast1",
    timeoutSeconds: 120,
    memory: "1GiB",
    invoker: "public",
    cors: true,
    secrets: [geminiApiKey],
  },
  async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({ error: { code: "method-not-allowed", message: "Use POST only." } });
      return;
    }

    try {
      const body = req.body || {};
      const imageBase64 = typeof body.imageBase64 === "string" ? body.imageBase64.trim() : "";
      const mimeType = typeof body.mimeType === "string" ? body.mimeType.trim() : "image/jpeg";

      if (!imageBase64) {
        res.status(400).json({ error: { code: "invalid-argument", message: "មិនមានរូបភាពសម្រាប់វិភាគទេ។" } });
        return;
      }

      const key = geminiApiKey.value();
      if (!key) {
        res.status(500).json({ error: { code: "failed-precondition", message: "GEMINI_API_KEY secret មិនទាន់បានកំណត់ក្នុង Firebase Functions ទេ។" } });
        return;
      }

      const models = await getModelsToTry(key);
      let lastError = null;

      for (const model of models) {
        try {
          const result = await callGenerateContent({ model, apiKey: key, imageBase64, mimeType });
          res.status(200).json(result);
          return;
        } catch (error) {
          lastError = error;
          const message = String(error && error.message ? error.message : error);
          if (message.includes("401") || message.includes("403") || message.toLowerCase().includes("api key")) {
            res.status(403).json({ error: { code: "permission-denied", message: "Gemini API key មិនត្រឹមត្រូវ ត្រូវបានបិទ ឬ Project មិនមានសិទ្ធិប្រើ API។" } });
            return;
          }
        }
      }

      res.status(500).json({ error: { code: "internal", message: lastError ? String(lastError.message || lastError) : "AI មិនអាចវិភាគបានទេ។" } });
    } catch (error) {
      res.status(500).json({ error: { code: "internal", message: String(error && error.message ? error.message : error) } });
    }
  }
);

async function getModelsToTry(apiKey) {
  try {
    const url = `https://generativelanguage.googleapis.com/v1beta/models?key=${encodeURIComponent(apiKey)}`;
    const response = await fetch(url);
    if (!response.ok) return preferredModels;

    const decoded = await response.json();
    const models = Array.isArray(decoded.models) ? decoded.models : [];
    const available = new Set();

    for (const item of models) {
      const rawName = typeof item.name === "string" ? item.name : "";
      const name = rawName.replace(/^models\//, "");
      const methods = Array.isArray(item.supportedGenerationMethods) ? item.supportedGenerationMethods : [];
      if (name && methods.includes("generateContent")) {
        available.add(name);
      }
    }

    const ordered = [
      ...preferredModels.filter((name) => available.has(name)),
      ...[...available].filter((name) => !preferredModels.includes(name)),
    ];

    return ordered.length ? ordered : preferredModels;
  } catch (_) {
    return preferredModels;
  }
}

async function callGenerateContent({ model, apiKey, imageBase64, mimeType }) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`;

  const body = {
    contents: [
      {
        role: "user",
        parts: [
          { text: prompt },
          {
            inlineData: {
              mimeType,
              data: imageBase64,
            },
          },
        ],
      },
    ],
    generationConfig: {
      temperature: 0.2,
      responseMimeType: "application/json",
    },
  };

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const text = await response.text().catch(() => "");
    throw new Error(`Gemini API error ${response.status}: ${text}`);
  }

  const decoded = await response.json();
  const text = extractGeminiText(decoded);
  if (!text) {
    throw new Error("Gemini did not return text.");
  }

  const jsonText = extractJsonObject(text);
  let result;
  try {
    result = JSON.parse(jsonText);
  } catch (error) {
    throw new Error(`Gemini returned invalid JSON: ${jsonText.slice(0, 300)}`);
  }

  return normalizeResult(result);
}

function extractGeminiText(decoded) {
  const candidates = Array.isArray(decoded.candidates) ? decoded.candidates : [];
  if (candidates.length) {
    const parts = candidates[0]?.content?.parts;
    if (Array.isArray(parts)) {
      const text = parts.map((part) => (typeof part.text === "string" ? part.text : "")).join("").trim();
      if (text) return text;
    }
  }

  if (typeof decoded.output_text === "string" && decoded.output_text.trim()) return decoded.output_text.trim();
  if (typeof decoded.outputText === "string" && decoded.outputText.trim()) return decoded.outputText.trim();
  return null;
}

function extractJsonObject(value) {
  let text = String(value).trim();
  if (text.startsWith("```")) {
    text = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "");
  }
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start >= 0 && end > start) {
    return text.substring(start, end + 1).trim();
  }
  return text;
}

function normalizeResult(value) {
  const result = value && typeof value === "object" && !Array.isArray(value) ? value : {};

  return {
    crop_kh: cleanText(result.crop_kh, "មិនអាចកំណត់បាន"),
    crop_en: cleanText(result.crop_en, "Unknown"),
    disease_kh: cleanText(result.disease_kh, "មិនអាចកំណត់បាន"),
    disease_en: cleanText(result.disease_en, "Unknown"),
    severity_kh: cleanText(result.severity_kh, "មិនច្បាស់"),
    confidence: cleanText(result.confidence, "មធ្យម"),
    symptoms_kh: cleanText(result.symptoms_kh, "មិនមានរោគសញ្ញាច្បាស់លាស់ក្នុងរូបភាពនេះទេ។"),
    treatment_kh: toStringArray(result.treatment_kh),
    prevention_kh: toStringArray(result.prevention_kh),
    warning_kh: cleanText(result.warning_kh, "លទ្ធផលនេះជាជំនួយពី AI ប៉ុណ្ណោះ។ សូមពិគ្រោះអ្នកជំនាញកសិកម្មមុនប្រើថ្នាំ។"),
  };
}

function cleanText(value, fallback) {
  const text = value == null ? "" : String(value).trim();
  return text || fallback;
}

function toStringArray(value) {
  if (Array.isArray(value)) {
    return value.map((item) => String(item).trim()).filter(Boolean);
  }
  if (typeof value === "string" && value.trim()) {
    return [value.trim()];
  }
  return [];
}

exports.predictSupplyHttp = onRequest(
  {
    region: "asia-southeast1",
    timeoutSeconds: 120,
    memory: "1GiB",
    invoker: "public",
    cors: true,
    secrets: [geminiApiKey],
  },
  async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({ error: { code: "method-not-allowed", message: "Use POST only." } });
      return;
    }

    try {
      const body = req.body || {};
      const crop = cleanText(body.crop, "ម្ទេស");
      const province = cleanText(body.province, "កំពង់ចាម");
      const harvestYear = Number(body.harvestYear || new Date().getFullYear());
      const harvestMonth = Number(body.harvestMonth || (new Date().getMonth() + 1));
      const userId = cleanText(body.userId, "");

      const db = admin.firestore();
      const [plantingSnap, productSnap, demandSnap, dealSnap] = await Promise.all([
        db.collection("planting_records").limit(500).get(),
        db.collection("product_listings").limit(500).get(),
        db.collection("buying_demands").limit(500).get(),
        db.collection("deals").limit(500).get(),
      ]);

      const plantings = plantingSnap.docs.map((doc) => ({ id: doc.id, ...doc.data() }))
        .filter((row) => sameText(row.crop, crop) && sameText(row.province, province) && Number(row.harvestYear) === harvestYear && Number(row.harvestMonth) === harvestMonth);

      const products = productSnap.docs.map((doc) => ({ id: doc.id, ...doc.data() }))
        .filter((row) => sameText(row.crop, crop) && sameText(row.province, province) && isActiveMarketRow(row));

      const demands = demandSnap.docs.map((doc) => ({ id: doc.id, ...doc.data() }))
        .filter((row) => sameText(row.crop, crop) && sameText(row.province, province) && isActiveMarketRow(row));

      const deals = dealSnap.docs.map((doc) => ({ id: doc.id, ...doc.data() }))
        .filter((row) => sameText(row.crop, crop) && (sameText(row.status, "Confirmed") || sameText(row.status, "Completed") || sameText(row.status, "Pending")));

      const supplyKg = sumNumbers(plantings, ["expectedKg", "quantity"]);
      const listedKg = sumNumbers(products, ["quantity"]);
      const demandKg = sumNumbers(demands, ["quantity"]);
      const dealKg = sumNumbers(deals, ["quantity"]);
      const avgProductPrice = averageNumbers(products, ["price"]);
      const avgTargetPrice = averageNumbers(demands, ["targetPrice", "price"]);
      const demandSupplyRatio = supplyKg > 0 ? demandKg / supplyKg : 0;
      const listedSupplyRatio = supplyKg > 0 ? listedKg / supplyKg : 0;

      const rulePrediction = buildSupplyRulePrediction({
        crop,
        province,
        harvestYear,
        harvestMonth,
        supplyKg,
        listedKg,
        demandKg,
        dealKg,
        avgProductPrice,
        avgTargetPrice,
        plantingCount: plantings.length,
        productCount: products.length,
        demandCount: demands.length,
        dealCount: deals.length,
        demandSupplyRatio,
        listedSupplyRatio,
      });

      let aiPrediction = rulePrediction;
      const key = geminiApiKey.value();
      if (key) {
        try {
          aiPrediction = await callSupplyGemini({ apiKey: key, data: rulePrediction });
        } catch (error) {
          aiPrediction = {
            ...rulePrediction,
            ai_note_kh: "AI recommendation fallback: Gemini មិនអាចបង្កើតអត្ថបទបានទេ។ ប្រើការគណនាតាមទិន្នន័យ Firestore ជំនួស។",
          };
        }
      }

      const response = {
        ...rulePrediction,
        ...aiPrediction,
        generatedAt: new Date().toISOString(),
        data_source: "Firestore + KasiAI Cloud AI",
      };

      await db.collection("supply_predictions").add({
        userId,
        crop,
        province,
        harvestYear,
        harvestMonth,
        ...response,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      res.status(200).json(response);
    } catch (error) {
      res.status(500).json({ error: { code: "internal", message: String(error && error.message ? error.message : error) } });
    }
  }
);

function sameText(a, b) {
  return String(a || "").trim().toLowerCase() === String(b || "").trim().toLowerCase();
}

function isActiveMarketRow(row) {
  const active = row.active !== false;
  const status = String(row.status || "Active").trim().toLowerCase();
  return active && status !== "completed" && status !== "deleted";
}

function firstNumber(row, keys) {
  for (const key of keys) {
    const value = Number(row[key]);
    if (Number.isFinite(value)) return value;
  }
  return 0;
}

function sumNumbers(rows, keys) {
  return rows.reduce((sum, row) => sum + firstNumber(row, keys), 0);
}

function averageNumbers(rows, keys) {
  const values = rows.map((row) => firstNumber(row, keys)).filter((value) => value > 0);
  if (!values.length) return 0;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function buildSupplyRulePrediction(data) {
  let statusKh = "មានតុល្យភាព";
  let riskLevelKh = "មធ្យម";
  let confidenceScore = 0.62;
  let marketSignalKh = "តម្រូវការ និងការផ្គត់ផ្គង់នៅកម្រិតត្រូវតាមដាន។";

  const netBalanceKg = data.supplyKg + data.listedKg - data.demandKg - data.dealKg;

  if (data.supplyKg <= 0 && data.listedKg <= 0) {
    statusKh = "ទិន្នន័យមិនគ្រប់គ្រាន់";
    riskLevelKh = "មិនច្បាស់";
    confidenceScore = 0.35;
    marketSignalKh = "មិនទាន់មានទិន្នន័យដាំដុះ ឬផលិតផលគ្រប់គ្រាន់សម្រាប់ទស្សន៍ទាយ។";
  } else if (netBalanceKg > Math.max(1000, data.demandKg * 0.35)) {
    statusKh = "អាចផ្គត់ផ្គង់លើស";
    riskLevelKh = "ខ្ពស់";
    confidenceScore = 0.82;
    marketSignalKh = "បរិមាណរំពឹងទុកលើសតម្រូវការដែលបានប្រមូលក្នុង Marketplace។";
  } else if (netBalanceKg < -Math.max(300, data.supplyKg * 0.25)) {
    statusKh = "អាចខ្វះផ្គត់ផ្គង់";
    riskLevelKh = "ខ្ពស់";
    confidenceScore = 0.80;
    marketSignalKh = "តម្រូវការទិញខ្ពស់ជាងទិន្នផលរំពឹងទុក។ អាចមានឱកាសលក់តម្លៃល្អ។";
  } else if (data.demandSupplyRatio >= 0.75) {
    statusKh = "តម្រូវការល្អ";
    riskLevelKh = "មធ្យម";
    confidenceScore = 0.72;
    marketSignalKh = "តម្រូវការទិញនៅជិតនឹងបរិមាណផ្គត់ផ្គង់។";
  }

  return {
    crop_kh: data.crop,
    province_kh: data.province,
    harvest_month: data.harvestMonth,
    harvest_year: data.harvestYear,
    predicted_supply_kg: Math.round(data.supplyKg),
    listed_supply_kg: Math.round(data.listedKg),
    buyer_demand_kg: Math.round(data.demandKg),
    deal_quantity_kg: Math.round(data.dealKg),
    net_balance_kg: Math.round(netBalanceKg),
    average_market_price: Number(data.avgProductPrice.toFixed(2)),
    average_target_price: Number(data.avgTargetPrice.toFixed(2)),
    planting_records: data.plantingCount,
    product_posts: data.productCount,
    demand_posts: data.demandCount,
    deal_records: data.dealCount,
    status_kh: statusKh,
    risk_level_kh: riskLevelKh,
    confidence_score: confidenceScore,
    market_signal_kh: marketSignalKh,
    recommendation_kh: buildDefaultSupplyRecommendation(statusKh),
    action_items_kh: buildDefaultSupplyActions(statusKh),
  };
}

function buildDefaultSupplyRecommendation(statusKh) {
  if (statusKh.includes("លើស")) {
    return "គួរបង្ហោះលក់មុនថ្ងៃប្រមូលផល ១–២ សប្តាហ៍ ភ្ជាប់ទៅអ្នកទិញធំ និងពិចារណាបញ្ចុះតម្លៃតិចតួចប្រសិនបើមានអ្នកលក់ច្រើន។";
  }
  if (statusKh.includes("ខ្វះ") || statusKh.includes("តម្រូវការល្អ")) {
    return "គួររៀបចំគុណភាពផលិតផល និងចរចាតម្លៃល្អ ព្រោះតម្រូវការទីផ្សារមានសញ្ញាល្អ។";
  }
  if (statusKh.includes("មិនគ្រប់គ្រាន់")) {
    return "បន្ថែមទិន្នន័យដាំដុះ ផលិតផល និងតម្រូវការទិញបន្ថែម ដើម្បីឱ្យប្រព័ន្ធទស្សន៍ទាយបានច្បាស់ជាងមុន។";
  }
  return "បន្តតាមដានតម្លៃ និងតម្រូវការទិញ។ បង្ហោះផលិតផលនៅ Marketplace មុនថ្ងៃប្រមូលផល។";
}

function buildDefaultSupplyActions(statusKh) {
  if (statusKh.includes("លើស")) {
    return ["បង្កើត post លក់ក្នុង Marketplace", "រក buyer មុនថ្ងៃប្រមូលផល", "បែងចែកការលក់ជាច្រើនដំណាក់កាល"];
  }
  if (statusKh.includes("ខ្វះ") || statusKh.includes("តម្រូវការល្អ")) {
    return ["រក្សាគុណភាព Grade A", "ចរចាតម្លៃជាមួយ buyer", "បង្កើត deal ឱ្យបានឆាប់"];
  }
  return ["បញ្ចូលទិន្នន័យបន្ថែម", "តាមដាន demand ក្នុង Marketplace", "ធ្វើ update ទិន្នផលរំពឹងទុករៀងរាល់សប្តាហ៍"];
}

async function callSupplyGemini({ apiKey, data }) {
  const models = await getModelsToTry(apiKey);
  const supplyPrompt = `
You are KasiAI supply predictor for Cambodian agriculture. Analyze this Firestore marketplace dataset and return ONLY valid JSON in Khmer.

Data:
${JSON.stringify(data, null, 2)}

Return this JSON shape only:
{
  "status_kh": "short status in Khmer",
  "risk_level_kh": "ទាប / មធ្យម / ខ្ពស់ / មិនច្បាស់",
  "confidence_score": 0.0,
  "market_signal_kh": "one useful Khmer sentence",
  "recommendation_kh": "professional Khmer recommendation for farmer and buyer",
  "action_items_kh": ["action 1", "action 2", "action 3"],
  "price_strategy_kh": "short price strategy in Khmer",
  "data_quality_kh": "explain if data is enough or not"
}
Rules:
- Use the numeric data. Do not invent external market data.
- Mention if data is still limited.
- Keep advice practical for Cambodian farmers.
`;

  let lastError = null;
  for (const model of models) {
    try {
      const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`;
      const response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: supplyPrompt }] }],
          generationConfig: { temperature: 0.2, responseMimeType: "application/json" },
        }),
      });

      if (!response.ok) {
        const text = await response.text().catch(() => "");
        throw new Error(`Gemini supply API error ${response.status}: ${text}`);
      }

      const decoded = await response.json();
      const text = extractGeminiText(decoded);
      const jsonText = extractJsonObject(text || "{}");
      const result = JSON.parse(jsonText);
      return {
        status_kh: cleanText(result.status_kh, data.status_kh),
        risk_level_kh: cleanText(result.risk_level_kh, data.risk_level_kh),
        confidence_score: Number(result.confidence_score || data.confidence_score || 0.62),
        market_signal_kh: cleanText(result.market_signal_kh, data.market_signal_kh),
        recommendation_kh: cleanText(result.recommendation_kh, data.recommendation_kh),
        action_items_kh: toStringArray(result.action_items_kh).length ? toStringArray(result.action_items_kh) : data.action_items_kh,
        price_strategy_kh: cleanText(result.price_strategy_kh, "ប្រើតម្លៃទីផ្សារបច្ចុប្បន្ន និងគុណភាពផលិតផលដើម្បីចរចា។"),
        data_quality_kh: cleanText(result.data_quality_kh, "ការទស្សន៍ទាយផ្អែកលើទិន្នន័យដែលមាននៅក្នុង Firestore បច្ចុប្បន្ន។"),
      };
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError || new Error("Gemini supply prediction failed");
}
