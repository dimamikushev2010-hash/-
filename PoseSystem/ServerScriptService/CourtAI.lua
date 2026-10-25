-- ModuleScript: ServerScriptService > CourtAI
-- «Живой суд»: реплики судьи, прокурора, адвоката и свидетелей.
--   🤖 Через нейросеть — Google Gemini или Claude (ключ — в Secrets, настройки — CourtConfig.AI): каждый раз новый спор и исход.
--   🎲 Без ключа, при ошибке или долгом ответе — живой спор без нейросети: характер судьи, доводы, протесты,
--      неожиданные повороты, весы правосудия и случайность.
-- Используют CourtServer (суд, чат адвоката) и DebugServer (проверка ключа).

local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("CourtConfig"))
local AI = Config.AI
local D = Config.Debate
local L = Config.Lines

local CourtAI = {}
local rng = Random.new()

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end
local function fill(text: string, vars): string
	return (string.gsub(text, "{(%w+)}", function(key)
		local v = vars[key]
		return v ~= nil and tostring(v) or "{" .. key .. "}"
	end))
end
-- Обрезать по символам (не по байтам — русские буквы занимают 2 байта)
local function cut(text: string, n: number): string
	local stop = utf8.offset(text, n + 1)
	if stop then
		return string.sub(text, 1, stop - 1) .. "…"
	end
	return text
end
local function shuffle(list)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

---------------------------------------------------------------------
-- 🤖 Запрос к Claude
---------------------------------------------------------------------

local key = nil
local keyChecked = false
local disabledUntil = 0 -- после ошибки — пауза (или навсегда, если ключ неверный)
local lastError = nil

-- Какая нейросеть: "gemini" (Google, есть бесплатный уровень) или "claude" (Anthropic)
local GEMINI = AI.Provider == "gemini"
local SECRET = GEMINI and AI.Gemini.SecretName or AI.SecretName
local MODEL = GEMINI and AI.Gemini.Model or AI.Model

local function secret()
	if not keyChecked then
		keyChecked = true
		local ok, value = pcall(function()
			return HttpService:GetSecret(SECRET)
		end)
		if ok and value then
			key = value
		else
			lastError = "нет секрета «" .. SECRET .. "»"
			print("[Court] Нейросеть суда выключена: " .. lastError .. " (Creator Hub → Secrets). Суд идёт живым спором без неё.")
		end
	end
	return key
end

function CourtAI.available(): boolean
	return AI.Enabled and os.clock() >= disabledUntil and secret() ~= nil
end

function CourtAI.status(): string
	if not AI.Enabled then
		return "выключена (CourtConfig.AI.Enabled = false)"
	end
	if not HttpService.HttpEnabled then
		return "нет доступа: Game Settings → Security → Allow HTTP Requests"
	end
	if not secret() then
		return "нет ключа: " .. tostring(lastError)
	end
	if os.clock() < disabledUntil then
		return "пауза после ошибки: " .. tostring(lastError)
	end
	return "готова (" .. MODEL .. ")" .. (lastError and (", последняя ошибка: " .. lastError) or "")
end

-- Фолбэк Claude при отказе модели — только там, где он есть
local function supportsFallback(model: string): boolean
	return string.find(model, "^claude%-opus%-5") ~= nil or string.find(model, "^claude%-fable") ~= nil or model == "claude-sonnet-5-5"
end

-- Схема ответа для Gemini: типы большими буквами, без additionalProperties
local function geminiSchema(schema)
	if type(schema) ~= "table" then
		return schema
	end
	local out = {}
	for k, v in schema do
		if k == "additionalProperties" then
			continue
		elseif k == "type" and type(v) == "string" then
			out.type = string.upper(v)
		elseif k == "properties" then
			out.properties = {}
			for name, sub in v do
				out.properties[name] = geminiSchema(sub)
			end
		elseif k == "items" then
			out.items = geminiSchema(v)
		else
			out[k] = v
		end
	end
	return out
end

-- Запрос к выбранной нейросети: Url, заголовки, тело
local function build(system: string, userText: string, schema, maxTokens: number)
	if GEMINI then
		local G = AI.Gemini
		local config = { maxOutputTokens = maxTokens }
		if schema then
			config.responseMimeType = "application/json"
			config.responseSchema = geminiSchema(schema)
		end
		if G.ThinkingBudget then
			config.thinkingConfig = { thinkingBudget = G.ThinkingBudget }
		end
		local safety = {}
		for _, category in { "HARM_CATEGORY_HARASSMENT", "HARM_CATEGORY_HATE_SPEECH", "HARM_CATEGORY_SEXUALLY_EXPLICIT", "HARM_CATEGORY_DANGEROUS_CONTENT" } do
			table.insert(safety, { category = category, threshold = G.SafetyThreshold })
		end
		return string.format(G.Url, G.Model), { ["Content-Type"] = "application/json", ["x-goog-api-key"] = key }, {
			systemInstruction = { parts = { { text = system } } },
			contents = { { role = "user", parts = { { text = userText } } } },
			generationConfig = config,
			safetySettings = safety,
		}
	end
	local body = {
		model = AI.Model,
		max_tokens = maxTokens,
		system = system,
		messages = { { role = "user", content = userText } },
		output_config = { effort = AI.Effort },
	}
	if schema then
		body.output_config.format = { type = "json_schema", schema = schema }
	end
	local headers = {
		["Content-Type"] = "application/json",
		["x-api-key"] = key,
		["anthropic-version"] = AI.ApiVersion,
	}
	if AI.Fallbacks and supportsFallback(AI.Model) then
		body.fallbacks = "default"
		headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
	end
	return AI.Url, headers, body
end

-- Текст из ответа (или nil и причина)
local function parse(data): (string?, string?)
	local parts = {}
	if GEMINI then
		if type(data.promptFeedback) == "table" and data.promptFeedback.blockReason then
			return nil, "запрос заблокирован фильтром Google"
		end
		local cand = type(data.candidates) == "table" and data.candidates[1]
		if type(cand) ~= "table" then
			return nil, "пустой ответ"
		end
		if cand.finishReason == "MAX_TOKENS" then
			return nil, "ответ обрезан (MaxTokens)"
		elseif cand.finishReason and cand.finishReason ~= "STOP" then
			return nil, "модель остановилась: " .. tostring(cand.finishReason)
		end
		for _, part in (type(cand.content) == "table" and cand.content.parts) or {} do
			if type(part) == "table" and type(part.text) == "string" and not part.thought then
				table.insert(parts, part.text)
			end
		end
	else
		if data.stop_reason == "refusal" then
			return nil, "модель отказалась"
		elseif data.stop_reason == "max_tokens" then
			return nil, "ответ обрезан (MaxTokens)"
		end
		for _, block in data.content or {} do
			if type(block) == "table" and block.type == "text" and type(block.text) == "string" then
				table.insert(parts, block.text)
			end
		end
	end
	if #parts == 0 then
		return nil, "пустой ответ"
	end
	return table.concat(parts), nil
end

-- Один запрос: system + одно сообщение пользователя. Возвращает текст ответа или nil
local function request(system: string, userText: string, schema, maxTokens: number): string?
	if not CourtAI.available() then
		return nil
	end
	local url, headers, body = build(system, userText, schema, maxTokens)
	local done, ok, res = false, false, nil
	task.spawn(function()
		ok, res = pcall(function()
			return HttpService:RequestAsync({ Url = url, Method = "POST", Headers = headers, Body = HttpService:JSONEncode(body) })
		end)
		done = true
	end)
	local deadline = os.clock() + AI.Timeout
	while not done and os.clock() < deadline do
		task.wait(0.1)
	end
	if not done then
		lastError = "долго не отвечала"
		return nil
	end
	if not ok then
		lastError = tostring(res)
		if string.find(lastError, "not enabled") then
			disabledUntil = math.huge -- HTTP выключен в настройках игры
		else
			disabledUntil = os.clock() + 30
		end
		warn("[Court] Нейросеть: " .. lastError)
		return nil
	end
	if res.StatusCode ~= 200 then
		lastError = "ошибка " .. res.StatusCode
		if res.StatusCode == 401 or res.StatusCode == 403 then
			disabledUntil = math.huge -- неверный ключ — до перезапуска сервера
		elseif res.StatusCode == 429 then
			lastError ..= " (кончился лимит запросов)"
			disabledUntil = os.clock() + 90
		elseif res.StatusCode >= 500 then
			disabledUntil = os.clock() + 60
		end
		warn("[Court] Нейросеть: " .. lastError .. " " .. string.sub(tostring(res.Body), 1, 300))
		return nil
	end
	local okJson, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
	if not okJson or type(data) ~= "table" then
		lastError = "непонятный ответ"
		return nil
	end
	local text, why = parse(data)
	lastError = why
	return text
end

-- Фильтр Roblox для текста, который увидят игроки (обязателен для созданного текста)
function CourtAI.filter(text: string, userId: number): string?
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat):GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" and result ~= "" then
		return result
	end
	return nil
end

---------------------------------------------------------------------
-- Дело текстом (для нейросети)
---------------------------------------------------------------------

local ROLES = { judge = true, prosecutor = true, lawyer = true, witness = true, police = true, court = true }
local KINDS = { none = true, acquit = true, fine = true, probation = true, community = true, prison = true }

local SCHEMA = {
	type = "object",
	additionalProperties = false,
	required = { "lines", "shift", "question", "verdict" },
	properties = {
		lines = {
			type = "array",
			items = {
				type = "object",
				additionalProperties = false,
				required = { "role", "name", "text", "evidence" },
				properties = {
					role = { type = "string", enum = { "judge", "prosecutor", "lawyer", "witness", "police", "court" } },
					name = { type = "string" },
					text = { type = "string" },
					evidence = { type = "string" },
				},
			},
		},
		shift = { type = "number" },
		question = {
			type = "object",
			additionalProperties = false,
			required = { "text", "options" },
			properties = {
				text = { type = "string" },
				options = { type = "array", items = { type = "string" } },
			},
		},
		verdict = {
			type = "object",
			additionalProperties = false,
			required = { "kind", "severity", "reason" },
			properties = {
				kind = { type = "string", enum = { "none", "acquit", "fine", "probation", "community", "prison" } },
				severity = { type = "number" },
				reason = { type = "string" },
			},
		},
	},
}

local VERDICT_RU = { acquit = "оправдать", fine = "только штраф", probation = "условный срок", community = "общественные работы", prison = "тюрьма" }

function CourtAI.factsText(ctx): string
	local out = {}
	local function add(s: string)
		table.insert(out, s)
	end
	add(string.format("ДЕЛО № %s", tostring(ctx.number)))
	add(string.format("Подсудимый: %s. Розыск: %d★. Убийств: %d (из них полицейских: %d). Ранений: %d.", ctx.defendant, ctx.stars, ctx.kills, ctx.policeKills, ctx.injuries))
	add("Что сообщали в полицию: " .. (#ctx.crimes > 0 and table.concat(ctx.crimes, "; ") or "нарушение порядка"))
	add("Улики:")
	if #ctx.evidence == 0 then
		add("- улик почти нет")
	end
	for _, e in ctx.evidence do
		if e.kind == "police" then
			add(string.format("- %s: офицер полиции видел подсудимого на месте сам", e.code))
		elseif e.kind == "witness" then
			add(string.format("- %s: свидетель %s (пришёл в суд), звонил в 911: «%s»", e.code, e.name, e.why))
		elseif e.kind == "call" then
			add(string.format("- %s: запись звонка в 911 свидетеля %s (сам в суд прийти не может): «%s»", e.code, e.name, e.why))
		elseif e.kind == "camera" then
			add(string.format("- %s: запись камеры «%s» в %s: %s", e.code, e.cam, e.time or "?", e.why))
		elseif e.kind == "lost" then
			add(string.format("- %s: камера «%s» была сломана до суда — её записи нет", e.code, e.cam))
		end
	end
	add(string.format("Допрос: признался в %d из 3 вопросов, соврал в %d.", ctx.confessed, ctx.lied))
	add("При аресте: " .. (ctx.surrendered and "не сопротивлялся, сдался сам" or ctx.resisted and "сопротивлялся (убегал, стрелял в полицию или задержан раненым)" or "обычно"))
	if ctx.probationBreach then
		add("ВАЖНО: подсудимый уже на условном сроке и снова попался.")
	end
	add(string.format("Судья: %s — %s.", ctx.judge.Name, ctx.judge.Mood))
	add(string.format("Прокурор: %s.", Config.ProsecutorName))
	add(string.format("Адвокат: %s, %s (сила %d из 5). Стиль: %s.", ctx.lawyer.Name, ctx.lawyer.Title, ctx.lawyer.Rating, ctx.lawyer.Style or ""))
	add("Друг-защитник: " .. (ctx.friend or "нет"))
	add(string.format("Весы сейчас: %.2f (от -1 — к оправданию, до 1 — к обвинению).", ctx.scale))
	local allowed = {}
	for _, k in ctx.allowed do
		table.insert(allowed, k .. " (" .. VERDICT_RU[k] .. ")")
	end
	add("Разрешённые исходы: " .. table.concat(allowed, ", ") .. ".")
	return table.concat(out, "\n")
end

local function transcriptText(ctx): string
	local out = {}
	local from = math.max(1, #ctx.transcript - 40)
	for i = from, #ctx.transcript do
		local l = ctx.transcript[i]
		table.insert(out, string.format("%s (%s): %s", l.name, l.role, l.text))
	end
	return #out > 0 and table.concat(out, "\n") or "(пока ничего)"
end

-- Проверить и почистить ответ нейросети
local function sanitize(ctx, data, userId: number)
	if type(data) ~= "table" or type(data.lines) ~= "table" then
		return nil
	end
	local seg = { lines = {}, shift = 0, question = nil, verdict = nil }
	for _, l in data.lines do
		if #seg.lines >= AI.MaxLines then
			break
		end
		if type(l) == "table" and ROLES[l.role] and type(l.text) == "string" and l.text ~= "" then
			local text = CourtAI.filter(cut(l.text, AI.MaxLine), userId)
			if text then
				local evidence = type(l.evidence) == "string" and ctx.codes[l.evidence] and l.evidence or nil
				local name = type(l.name) == "string" and cut(l.name, 30) or ""
				table.insert(seg.lines, { role = l.role, name = name, text = text, evidence = evidence })
			end
		end
	end
	seg.shift = type(data.shift) == "number" and math.clamp(data.shift, -0.4, 0.4) or 0
	local q = data.question
	if type(q) == "table" and type(q.text) == "string" and q.text ~= "" and type(q.options) == "table" and #q.options >= 2 then
		local text = CourtAI.filter(cut(q.text, AI.MaxLine), userId)
		local options = {}
		for _, o in q.options do
			if type(o) == "string" and o ~= "" and #options < 4 then
				local f = CourtAI.filter(cut(o, 110), userId)
				if f then
					table.insert(options, f)
				end
			end
		end
		if text and #options >= 2 then
			seg.question = { text = text, options = options }
		end
	end
	local v = data.verdict
	if type(v) == "table" and KINDS[v.kind] and v.kind ~= "none" then
		seg.verdict = {
			kind = v.kind,
			severity = type(v.severity) == "number" and math.clamp(v.severity, 0, 1) or 0.5,
			reason = type(v.reason) == "string" and CourtAI.filter(cut(v.reason, AI.MaxLine), userId) or nil,
		}
	end
	if #seg.lines == 0 and not seg.verdict then
		return nil
	end
	return seg
end

-- Часть суда через нейросеть. promptIndex — номер задания в CourtConfig.AI.Parts
function CourtAI.segment(ctx, promptIndex: number, protest: boolean, userId: number)
	local task_ = fill(AI.Parts[promptIndex] or AI.Parts[#AI.Parts], { friend = ctx.friend or "" })
	if protest then
		task_ ..= "\n" .. AI.ProtestNote
	end
	local userText = CourtAI.factsText(ctx) .. "\n\nСТЕНОГРАММА (что уже сказано):\n" .. transcriptText(ctx) .. "\n\nЗАДАНИЕ: " .. task_
	local text = request(AI.CourtPrompt, userText, SCHEMA, AI.MaxTokens)
	if not text then
		return nil
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, text)
	if not ok then
		lastError = "ответ не JSON"
		return nil
	end
	local seg = sanitize(ctx, data, userId)
	if not seg then
		lastError = "пустая часть суда"
	end
	return seg
end

-- Ответ адвоката на свой текст подзащитного (КПЗ)
function CourtAI.lawyerReply(ctx, history, text: string, userId: number): string?
	if not AI.LawyerChat then
		return nil
	end
	local system = AI.LawyerPrompt .. string.format("\nТы: %s, %s. Твой стиль: %s.", ctx.lawyer.Name, ctx.lawyer.Title, ctx.lawyer.Style or "")
	local lines = {}
	for i = math.max(1, #history - 8), #history do
		table.insert(lines, history[i])
	end
	local userText = CourtAI.factsText(ctx)
		.. "\n\nНЕДАВНИЙ РАЗГОВОР:\n"
		.. (#lines > 0 and table.concat(lines, "\n") or "(начало)")
		.. "\n\nПодзащитный пишет: «"
		.. cut(text, 300)
		.. "»\nОтветь одной короткой репликой адвоката."
	local reply = request(system, userText, nil, 2000)
	if not reply then
		return nil
	end
	return CourtAI.filter(cut(reply, 300), userId)
end

---------------------------------------------------------------------
-- 🎲 Живой спор без нейросети
---------------------------------------------------------------------

local function line(seg, role: string, name: string, text: string, evidence: string?)
	table.insert(seg.lines, { role = role, name = name, text = text, evidence = evidence })
end

local function names(ctx)
	return { judge = ctx.judge.Name, prosecutor = Config.ProsecutorName, lawyer = ctx.lawyer.Name, police = "Офицер полиции", court = "", witness = "Свидетель" }
end

local function protestLines(ctx, seg)
	local n = names(ctx)
	line(seg, "lawyer", n.lawyer, pick(D.Protest))
	local chance = ctx.judge.Accept * (0.6 + ctx.lawyer.Rating * 0.1)
	if rng:NextNumber() < chance then
		line(seg, "judge", n.judge, pick(D.ProtestYes))
		seg.shift -= 0.1
	else
		line(seg, "judge", n.judge, pick(D.ProtestNo))
		seg.shift += 0.03
	end
end

local function twist(ctx, seg, chance: number)
	if rng:NextNumber() >= chance then
		return
	end
	local hasWitness = false
	for _, e in ctx.evidence do
		hasWitness = hasWitness or e.kind == "witness"
	end
	local list = {}
	for _, t in D.Twists do
		if not t.NeedWitness or hasWitness then
			table.insert(list, t)
		end
	end
	if #list == 0 then
		return
	end
	local t = pick(list)
	local n = names(ctx)
	for _, l in t.Lines do
		line(seg, l[1], n[l[1]] or "", l[2])
	end
	seg.shift += t.Shift
end

local function strengthOfScale(scale: number): string
	return scale < -0.2 and "Weak" or scale < 0.3 and "Medium" or "Strong"
end

-- part: 1 обвинение, 2 защита + вопрос, 3 реакция (+ слово другу), 4 заключение + последнее слово, 5 приговор
function CourtAI.offline(ctx, part: number, protest: boolean)
	local seg = { lines = {}, shift = 0, question = nil, verdict = nil }
	local n = names(ctx)
	local vars = { number = ctx.number, player = ctx.defendant, crimes = #ctx.crimes > 0 and table.concat(ctx.crimes, ", ") or "нарушение общественного порядка" }
	if protest then
		protestLines(ctx, seg)
	end
	if part == 0 then
		return seg -- только протест
	end
	local doubt = math.clamp(ctx.lawyer.DoubtWitness + (ctx.judge.Accept - 0.45) * 0.3, 0, 0.9)
	if part == 1 then
		line(seg, "judge", n.judge, fill(pick(ctx.judge.Open), vars))
		line(seg, "prosecutor", n.prosecutor, fill(pick(L.ProsecutorCharge), vars))
		local shown = { witness = 0, camera = 0 }
		for _, e in ctx.evidence do
			if e.kind == "police" then
				line(seg, "prosecutor", n.prosecutor, pick(D.ProsecutorPolice))
				line(seg, "police", n.police, pick(L.PoliceSay), e.code)
			elseif e.kind == "witness" or e.kind == "call" then
				shown.witness += 1
				if shown.witness > 3 then
					seg.shift += 0.04
					continue
				end
				local wv = { name = e.name, why = e.why, Why = e.Why or e.why }
				line(seg, "prosecutor", n.prosecutor, fill(pick(L.ProsecutorWitness), wv))
				if e.kind == "call" then
					line(seg, "prosecutor", n.prosecutor, fill(pick(L.WitnessDead), wv), e.code)
					seg.shift += 0.05
				else
					line(seg, "witness", e.name, fill(pick(L.WitnessSay), wv), e.code)
					if rng:NextNumber() < doubt then
						line(seg, "lawyer", n.lawyer, pick(L.LawyerDoubtWitness))
						line(seg, "witness", e.name, pick(L.WitnessUnsure))
						seg.shift -= 0.12
					elseif rng:NextNumber() < 0.5 then
						line(seg, "lawyer", n.lawyer, pick(L.LawyerDoubtWitness))
						line(seg, "witness", e.name, pick(D.WitnessFirm))
						seg.shift += 0.08
					else
						seg.shift += 0.06
					end
				end
			elseif e.kind == "camera" then
				shown.camera += 1
				if shown.camera > 3 then
					seg.shift += 0.04
					continue
				end
				local cv = { cam = e.cam, why = e.why }
				line(seg, "prosecutor", n.prosecutor, fill(pick(L.ProsecutorCamera), cv))
				line(seg, "court", "Запись камеры", fill(L.CameraShow, cv), e.code)
				if rng:NextNumber() < ctx.lawyer.DoubtCamera + (ctx.judge.Accept - 0.45) * 0.2 then
					line(seg, "lawyer", n.lawyer, pick(L.LawyerDoubtCamera))
					line(seg, "judge", n.judge, pick(L.JudgeRejectCamera))
					seg.shift -= 0.12
				else
					line(seg, "judge", n.judge, pick(D.JudgeAcceptCamera))
					seg.shift += 0.1
				end
			elseif e.kind == "lost" then
				line(seg, "prosecutor", n.prosecutor, fill(pick(L.CameraLost), { cam = e.cam }), e.code)
				seg.shift -= 0.03
			end
		end
		if #ctx.evidence == 0 then
			line(seg, "lawyer", n.lawyer, "Ваша честь, а где улики? Я ничего не вижу.")
			line(seg, "judge", n.judge, pick(L.NoWitnesses))
			seg.shift -= 0.15
		end
	elseif part == 2 then
		local args = shuffle(table.clone(D.DefenseArgs))
		for i = 1, math.min(2, #args) do
			line(seg, "lawyer", n.lawyer, args[i].Text)
			seg.shift += args[i].Shift * (0.6 + ctx.lawyer.Rating * 0.12)
			if rng:NextNumber() < 0.6 then
				local r = pick(D.ProsecutorRebuttals)
				line(seg, "prosecutor", n.prosecutor, r.Text)
				seg.shift += r.Shift
			end
			if rng:NextNumber() < 0.45 then
				line(seg, "judge", n.judge, pick(ctx.judge.Comment))
			end
		end
		twist(ctx, seg, D.TwistChance * 0.5)
		local q = pick(D.Questions)
		local options = shuffle(table.clone(q.Options))
		ctx.optionShifts = {}
		local texts = {}
		for i, o in options do
			texts[i] = o[1]
			ctx.optionShifts[i] = o[2]
		end
		line(seg, rng:NextNumber() < 0.5 and "judge" or "prosecutor", rng:NextNumber() < 0.5 and n.judge or n.prosecutor, q.Text)
		seg.lines[#seg.lines].name = n[seg.lines[#seg.lines].role]
		seg.question = { text = q.Text, options = texts }
	elseif part == 3 then
		local a = ctx.answerShift or 0
		if a < 0 then
			line(seg, "judge", n.judge, pick(D.ReactGood))
		elseif a > 0.05 then
			line(seg, "judge", n.judge, pick(D.ReactBad))
			line(seg, "prosecutor", n.prosecutor, pick(D.ProsecutorRebuttals).Text)
		else
			line(seg, "judge", n.judge, pick(ctx.judge.Comment))
		end
		twist(ctx, seg, D.TwistChance)
		if ctx.friend then
			line(seg, "judge", n.judge, fill(L.JudgeFriend, { name = ctx.friend }))
			local options = {}
			ctx.optionShifts = {}
			for i, s in shuffle(table.clone(Config.FriendSpeeches)) do
				if i > 3 then
					break
				end
				table.insert(options, fill(s.Text, vars))
				ctx.optionShifts[#options] = s.Effect
			end
			seg.question = { text = "Что скажешь в защиту?", options = options }
		end
	elseif part == 4 then
		local st = strengthOfScale(ctx.scale)
		line(seg, "prosecutor", n.prosecutor, pick(D.ProsecutorClose[st]))
		local speeches = Config.DefenseSpeech[ctx.lawyer.Id] or Config.DefenseSpeech.Public
		line(seg, "lawyer", n.lawyer, fill(pick(speeches[st] or speeches.Medium), vars))
		seg.shift -= 0.04 * ctx.lawyer.Rating
		if rng:NextNumber() < 0.35 then
			line(seg, "prosecutor", n.prosecutor, pick(D.ProsecutorRebuttals).Text)
		end
		line(seg, "judge", n.judge, pick(D.JudgeLastWord))
		local options = {}
		ctx.optionShifts = {}
		for _, w in shuffle(table.clone(Config.LastWord)) do
			table.insert(options, w.Text)
			ctx.optionShifts[#options] = w.Effect * 1.5
		end
		seg.question = { text = "Последнее слово", options = options }
	else
		-- Приговор: весы + случайность
		local V = Config.Verdict
		local s = ctx.scale + rng:NextNumber(-V.Noise, V.Noise)
		local kind
		if s < V.Acquit then
			kind = "acquit"
		elseif s < V.Fine then
			kind = "fine"
		elseif s < V.Probation then
			kind = "probation"
		elseif s < V.Community then
			kind = "community"
		else
			kind = "prison"
		end
		line(seg, "judge", n.judge, kind == "acquit" and "Суд выслушал стороны. Сомнения толкуются в пользу подсудимого." or "Суд выслушал стороны и изучил доказательства.")
		seg.verdict = { kind = kind, severity = math.clamp((s + 1) / 2, 0, 1), reason = nil }
	end
	return seg
end

return CourtAI
