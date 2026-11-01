import Foundation

// Puff battles: at the start of each season every player gets an egg that hatches into a randomly generated pet
// (original designs drawn as SVG). Daily Health numbers feed it: the day's growth points are EXP, and each growth
// element trains one stat. Every day, all hatched pets battle each other. Pets, battles and their logs are seeded from
// names and dates, so every render of the page gives the same results.

struct RNG {  // SplitMix64, seeded with an FNV-1a hash of a string (stable across runs, unlike Hasher)
    var s: UInt64
    init(_ text: String) {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        s = h
    }
    mutating func next() -> UInt64 {
        s &+= 0x9e37_79b9_7f4a_7c15
        var z = s
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
    mutating func double() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func pick<T>(_ a: [T]) -> T { a[int(a.count)] }
}

/// Water douses Fire, Fire burns Leaf, Leaf grounds Spark, Spark shocks Water.
enum PetElement: Int, CaseIterable {
    case water, fire, leaf, spark

    var emoji: String { ["💧", "🔥", "🍃", "⚡"][rawValue] }
    func name(_ lang: String) -> String { (lang == "zh" ? ["水", "火", "叶", "电"] : ["Water", "Fire", "Leaf", "Spark"])[rawValue] }
    /// Water douses Fire, Fire burns Leaf, Leaf grounds Spark, Spark shocks Water.
    var beats: PetElement { PetElement(rawValue: (rawValue + 1) % 4)! }
    var bodies: [String] { [["#7cc4f5", "#69b8f0", "#8fd3e8"], ["#ff9b6b", "#ff8a5c", "#ffb072"], ["#8fd18b", "#7cc792", "#a6d977"], ["#ffd65c", "#ffcc4d", "#f5df7a"]][rawValue] }
    var belly: String { ["#e8f6ff", "#fff0e2", "#effae6", "#fffbe6"][rawValue] }
    var dark: String { ["#2d6f9e", "#b44a24", "#3f7d3a", "#a8831a"][rawValue] }
}

enum SkillKind { case attack, multi, heal, shield, burn, bind, paralyze, charge, recoil, passive }

/// Skills. Tier 0 = the element's own three (unlocked at Lv 1 / 5 / 10); 1 rare, 2 epic, 3 legendary signature.
/// Several read today's Health numbers, so how you lived today changes how they work.
struct Skill {
    let id: String, zh: String, en: String, emoji: String
    let tier: Int, kind: SkillKind, power: Double, hits: Int, unlock: Int
    var ignoreShield = false, ignoreType = false
    let zhDesc: String, enDesc: String

    func name(_ lang: String) -> String { lang == "zh" ? zh : en }
    func desc(_ lang: String) -> String { lang == "zh" ? zhDesc : enDesc }

    static let all: [Skill] = [
        // water
        Skill(id: "bubble", zh: "泡泡冲击", en: "Bubble Rush", emoji: "🫧", tier: 0, kind: .attack, power: 1, hits: 1, unlock: 1, zhDesc: "普通攻击", enDesc: "A plain hit"),
        Skill(id: "drizzle", zh: "治愈细雨", en: "Healing Drizzle", emoji: "🌦️", tier: 0, kind: .heal, power: 0.15, hits: 1, unlock: 5, zhDesc: "回复 15% 体力，昨晚睡得越好回得越多（最多 30%）", enDesc: "Heals 15% HP, more the better you slept (up to 30%)"),
        Skill(id: "tide", zh: "潮汐护盾", en: "Tide Shield", emoji: "🌊", tier: 0, kind: .shield, power: 0.5, hits: 1, unlock: 10, zhDesc: "下一次受到的伤害减半", enDesc: "Halves the next hit taken"),
        // fire
        Skill(id: "ember", zh: "小火球", en: "Ember Puff", emoji: "🔥", tier: 0, kind: .attack, power: 1, hits: 1, unlock: 1, zhDesc: "普通攻击", enDesc: "A plain hit"),
        Skill(id: "scorch", zh: "灼烧", en: "Scorch", emoji: "♨️", tier: 0, kind: .burn, power: 0.06, hits: 3, unlock: 5, zhDesc: "让对手烧伤 3 回合，每回合掉 6% 体力", enDesc: "Burns the foe for 3 turns, 6% HP each"),
        Skill(id: "blaze", zh: "烈焰冲刺", en: "Blaze Dash", emoji: "☄️", tier: 0, kind: .recoil, power: 1.5, hits: 1, unlock: 10, zhDesc: "1.5 倍伤害，自己也掉 8% 体力", enDesc: "1.5× damage, costs 8% of your own HP"),
        // leaf
        Skill(id: "twirl", zh: "叶子旋风", en: "Leaf Twirl", emoji: "🍃", tier: 0, kind: .attack, power: 1, hits: 1, unlock: 1, zhDesc: "普通攻击", enDesc: "A plain hit"),
        Skill(id: "photo", zh: "光合作用", en: "Photosynthesis", emoji: "🌞", tier: 0, kind: .heal, power: 0.10, hits: 1, unlock: 5, zhDesc: "回复 10% 体力，今天步数越多回得越多（最多 30%）", enDesc: "Heals 10% HP, more the more you walked today (up to 30%)"),
        Skill(id: "vine", zh: "藤蔓缠绕", en: "Vine Bind", emoji: "🌿", tier: 0, kind: .bind, power: 0.6, hits: 1, unlock: 10, zhDesc: "对手下回合有 60% 动不了", enDesc: "60% chance the foe loses its next turn"),
        // spark
        Skill(id: "zap", zh: "噼啪电击", en: "Zap Pop", emoji: "⚡", tier: 0, kind: .attack, power: 1, hits: 1, unlock: 1, zhDesc: "普通攻击", enDesc: "A plain hit"),
        Skill(id: "flash", zh: "电光一闪", en: "Double Flash", emoji: "✴️", tier: 0, kind: .multi, power: 0.6, hits: 2, unlock: 5, zhDesc: "连击 2 次，每次 0.6 倍", enDesc: "Hits twice at 0.6× each"),
        Skill(id: "para", zh: "麻痹", en: "Static Jolt", emoji: "🌀", tier: 0, kind: .paralyze, power: 0.3, hits: 3, unlock: 10, zhDesc: "对手 3 回合内每回合 30% 动不了（每场限 1 次）", enDesc: "For 3 turns, the foe has a 30% chance to lose each turn (once a battle)"),
        // rare: passives
        Skill(id: "streak", zh: "连胜之魂", en: "Streak Spirit", emoji: "🔥", tier: 1, kind: .passive, power: 0.06, hits: 1, unlock: 1, zhDesc: "被动：连续达标每天伤害 +6%（最多 +30%）", enDesc: "Passive: +6% damage per streak day (up to +30%)"),
        Skill(id: "nap", zh: "午睡反击", en: "Nap Counter", emoji: "😴", tier: 1, kind: .passive, power: 1.2, hits: 1, unlock: 1, zhDesc: "被动：犯困打哈欠时，改为 1.2 倍反击", enDesc: "Passive: when it would yawn, it counterattacks at 1.2× instead"),
        Skill(id: "sweat", zh: "汗水护甲", en: "Sweat Armor", emoji: "💦", tier: 1, kind: .passive, power: 0.2, hits: 1, unlock: 1, zhDesc: "被动：今天活动量达标时，受到的伤害 −20%", enDesc: "Passive: takes 20% less damage when today's activity is on target"),
        // epic
        Skill(id: "charge", zh: "万步冲锋", en: "10k-Step Charge", emoji: "🏃", tier: 2, kind: .charge, power: 1, hits: 1, unlock: 1, zhDesc: "伤害 = 1 + 1.5 × 今天步数完成度（1 万步时 2.5 倍）", enDesc: "Damage = 1 + 1.5 × today's step progress (2.5× at 10,000 steps)"),
        Skill(id: "deep", zh: "深度睡眠", en: "Deep Sleep", emoji: "🛌", tier: 2, kind: .passive, power: 0.4, hits: 1, unlock: 1, zhDesc: "被动：倒下时站起来一次，昨晚睡够 7 小时回 40% 体力，否则 20%", enDesc: "Passive: gets back up once when knocked out, with 40% HP after 7+ h of sleep, else 20%"),
        Skill(id: "still", zh: "心如止水", en: "Still Heart", emoji: "🧘", tier: 2, kind: .passive, power: 0.3, hits: 1, unlock: 1, zhDesc: "被动：心率越平稳，越容易闪开攻击（最多 30%）", enDesc: "Passive: the calmer your heart, the likelier it dodges (up to 30%)"),
        // legendary signatures
        Skill(id: "meteor", zh: "流星雨", en: "Meteor Shower", emoji: "🌠", tier: 3, kind: .multi, power: 0.5, hits: 3, unlock: 1, ignoreShield: true, zhDesc: "星空团专属：连击 3 次，无视护盾", enDesc: "Starry Puff only: 3 hits, ignores shields"),
        Skill(id: "rainbow", zh: "彩虹光束", en: "Rainbow Beam", emoji: "🌈", tier: 3, kind: .attack, power: 1.5, hits: 1, unlock: 1, ignoreType: true, zhDesc: "彩虹团专属：1.5 倍伤害，不受属性克制影响", enDesc: "Rainbow Puff only: 1.5× damage, unaffected by elements"),
    ]
    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static let elementSkills = [["bubble", "drizzle", "tide"], ["ember", "scorch", "blaze"], ["twirl", "photo", "vine"], ["zap", "flash", "para"]]
}

enum Rarity {
    static func name(_ r: Int, _ lang: String) -> String { (lang == "zh" ? ["普通", "稀有", "史诗", "传说"] : ["Common", "Rare", "Epic", "Legendary"])[r] }
    static let colors = ["#8a8f98", "#3a86ff", "#9b5de5", "#f4a100"]
    static let odds = [65, 25, 8, 2]  // percent
    static let statBonus = [1.0, 1.02, 1.04, 1.06]  // small: habits should matter more than luck
}

struct Pet {
    let owner: String
    let element: PetElement
    let rarity: Int  // 0 common … 3 legendary
    let species: Int  // 0 puff, 1 starry (legendary), 2 rainbow (legendary)
    let zhName: String, enName: String
    let body: String
    let ears: Int, pattern: Int, tail: Int, eyes: Int
    let shiny: Bool
    let extra: [String]  // rarity skills, known from hatching

    func name(_ lang: String) -> String {
        let n = lang == "zh" ? zhName : enName
        return species == 0 ? n : n + (lang == "zh" ? ["", "（星空团）", "（彩虹团）"][species] : ["", " (Starry)", " (Rainbow)"][species])
    }

    /// Skills it can use at a level: the element's own as they unlock, plus its rarity skills.
    func skills(level: Int) -> [Skill] {
        Skill.elementSkills[element.rawValue].compactMap { Skill.byID[$0] }.filter { $0.unlock <= level } + extra.compactMap { Skill.byID[$0] }
    }

    /// The egg's contents are fixed by the owner and the season, so the same pet hatches on every render.
    static func hatch(_ owner: String, season: Int) -> Pet {
        var r = RNG("puff|\(owner)|\(season)")
        let el = PetElement(rawValue: r.int(4))!
        let roll = r.int(100)
        let rarity = roll < 2 ? 3 : roll < 10 ? 2 : roll < 35 ? 1 : 0
        let species = rarity == 3 ? 1 + r.int(2) : 0
        let zh = ["嘟", "噜", "咪", "啾", "糯", "豆", "球", "乐", "皮", "波", "奇", "米", "哆", "莉", "团", "卡"]
        let en = ["Pip", "Momo", "Bobo", "Taro", "Nana", "Kiki", "Lulu", "Popo", "Dodo", "Mimi", "Bean", "Puff", "Zuzu", "Nori", "Tofu", "Coco"]
        let a = r.int(16), b = r.int(16)
        let shiny = r.int(20) == 0
        var extra: [String] = []
        if rarity >= 1 { extra.append(r.pick(["streak", "nap", "sweat"])) }
        if rarity >= 2 { extra.append(r.pick(["charge", "deep", "still"])) }
        if rarity == 3 { extra.append(species == 1 ? "meteor" : "rainbow") }
        let body = species == 1 ? "#2b3a67" : species == 2 ? "url(#rb-\(Pets.uid(owner)))" : shiny ? "#c9a7ff" : r.pick(el.bodies)
        return Pet(owner: owner, element: el, rarity: rarity, species: species, zhName: zh[a] + zh[b], enName: en[a], body: body,
                   ears: r.int(4), pattern: r.int(4), tail: r.int(3), eyes: r.int(3), shiny: shiny, extra: extra)
    }
}

struct Stats {
    var hp = 40.0, atk = 10.0, def = 8.0, spd = 8.0
}

/// Today's mood from today's numbers; it changes how the pet fights today.
struct Condition {
    var sleepy = false, pumped = false, focused = false, energetic = false, sluggish = false
}

struct PetResult {
    let owner: String
    let pet: Pet
    let exp: Double
    let stats: Stats
    let condition: Condition
    let hasToday: Bool
    let metrics: [String: Double]
    let todayE: [Double]  // sun, water, nutrients, calm on the day; 0.5 when not measured
    let streak: Int
    var wins = 0, losses = 0

    static let hatchAt = 15.0
    var hatched: Bool { exp >= Self.hatchAt }
    var level: Int { hatched ? min(30, 1 + Int((exp - Self.hatchAt) / 7)) : 0 }
    var stage: Int { !hatched ? 0 : level < 5 ? 1 : level < 10 ? 2 : 3 }  // egg, baby, junior, adult
    var skills: [Skill] { pet.skills(level: level) }
}

struct Battle {
    let a: String, b: String
    let winner: String
    let log: [String]
}

enum Pets {
    /// A short id for SVG gradients, unique per owner on the page.
    static func uid(_ s: String) -> String {
        var g = RNG("uid|" + s)
        return String(g.next() % 1_000_000)
    }

    static func stageName(_ i: Int, _ lang: String) -> String {
        (lang == "zh" ? ["蛋", "幼崽", "少年", "成年"] : ["Egg", "Baby", "Junior", "Adult"])[i]
    }

    /// Feed each player's pet day by day up to `day`: EXP = the day's growth points (elements weighted equally, the
    /// garden's streak bonus), and each element trains one stat. Returns the pets as of that day.
    static func state(_ ledger: Ledger, dates: [String], season: Int, upTo day: String) -> [PetResult] {
        ledger.players.map { owner, byDate in
            let pet = Pet.hatch(owner, season: season)
            var st = Stats()
            switch pet.element { case .water: st.hp += 10; case .fire: st.atk += 3; case .leaf: st.def += 3; case .spark: st.spd += 3 }
            var exp = 0.0, streak = 0
            var cond = Condition(sluggish: true)
            var todayE = [0.5, 0.5, 0.5, 0.5]
            for d in dates where d <= day {
                guard let g = byDate[d] else { streak = 0; continue }
                let prev = (1...7).compactMap { byDate[Garden.add(d, -$0)]?.metrics["resting_hr"] }
                let e = Garden.elements(g.metrics, baselineHR: prev.count >= 2 ? prev.reduce(0, +) / Double(prev.count) : nil)
                let v = e.map { $0 ?? 0.5 }
                let pts = 10 * v.reduce(0, +) / 4
                streak = pts >= 7 ? streak + 1 : 0
                exp += pts + (streak >= 3 ? 1 : 0)
                st.hp += 3 + 4 * v[1]
                st.atk += 1 + 2 * v[0]
                st.def += 1 + 2 * v[3]
                st.spd += 1 + 2 * v[2]
                if d == day {
                    todayE = v
                    cond = Condition(sleepy: (e[1] ?? 1) < 0.45, pumped: (e[0] ?? 0) >= 1, focused: (e[3] ?? 0) >= 0.95, energetic: (e[2] ?? 0) >= 1)
                }
            }
            let k = Rarity.statBonus[pet.rarity]
            st = Stats(hp: st.hp * k, atk: st.atk * k, def: st.def * k, spd: st.spd * k)
            return PetResult(owner: owner, pet: pet, exp: exp, stats: st, condition: cond, hasToday: byDate[day] != nil,
                             metrics: byDate[day]?.metrics ?? [:], todayE: todayE, streak: byDate[day] != nil ? streak : 0)
        }
        .sorted { $0.owner < $1.owner }
    }

    static func battle(_ x: PetResult, _ y: PetResult, day: String, lang: String) -> Battle {
        func t(_ en: String, _ zh: String) -> String { lang == "zh" ? zh : en }
        var r = RNG("battle|\(day)|\(x.owner)|\(y.owner)")
        struct F {
            let p: PetResult
            var hp: Double, maxHP: Double
            let atk, def, spd, crit, yawn: Double
            var burn = 0, para = 0, bound = false, shield = false, revived = false, heals = 0
            var uses: [String: Int] = [:]  // status moves are limited so a battle cannot become a stun-lock
            func has(_ id: String) -> Bool { p.skills.contains { $0.id == id } }
        }
        func fighter(_ p: PetResult) -> F {
            let c = p.condition, k = c.sluggish ? 0.9 : 1
            return F(p: p, hp: p.stats.hp * k, maxHP: p.stats.hp * k, atk: p.stats.atk * k * (c.pumped ? 1.15 : 1), def: p.stats.def * k,
                     spd: p.stats.spd * k * (c.sleepy ? 0.7 : 1) * (c.energetic ? 1.1 : 1), crit: c.focused ? 0.18 : 0.08, yawn: c.sleepy ? 0.15 : 0)
        }
        var f = [fighter(x), fighter(y)]
        let names = [x.pet.name(lang), y.pet.name(lang)]
        var log: [String] = []
        func say(_ s: String) { log.append(s) }

        /// One hit from f[i] on the other; returns the damage dealt (0 = dodged).
        func hit(_ i: Int, _ power: Double, _ sk: Skill) -> Double {
            let j = 1 - i
            let a = f[i], d = f[j]
            if d.has("still"), r.double() < 0.3 * d.p.todayE[3] {
                say(t("\(names[j]) dodged with Still Heart 🧘", "\(names[j]) 心如止水，闪开了 🧘"))
                return 0
            }
            let strong = !sk.ignoreType && a.p.pet.element.beats == d.p.pet.element
            let weak = !sk.ignoreType && d.p.pet.element.beats == a.p.pet.element
            let crit = r.double() < a.crit
            var dmg = max(1, a.atk * power * (strong ? 1.5 : weak ? 0.7 : 1) * (0.85 + 0.15 * r.double()) - d.def * 0.4) * (crit ? 1.6 : 1)
            if a.has("streak") { dmg *= 1 + 0.06 * Double(min(a.p.streak, 5)) }
            if d.has("sweat"), d.p.todayE[2] >= 0.8 { dmg *= 0.8 }
            if d.shield, !sk.ignoreShield { dmg *= 0.5; f[j].shield = false }
            f[j].hp -= dmg
            var line = "\(sk.emoji) " + t("\(names[i]) used \(sk.name(lang)): \(Int(dmg.rounded())) damage", "\(names[i]) 使出「\(sk.name(lang))」，造成 \(Int(dmg.rounded())) 点伤害")
            if strong { line += t(", super effective!", "，效果拔群！") }
            if crit { line += t(" Critical!", " 暴击！") }
            say(line)
            return dmg
        }

        /// Knocked out? Deep Sleep gets it back up once.
        func down(_ j: Int) -> Bool {
            guard f[j].hp <= 0 else { return false }
            if f[j].has("deep"), !f[j].revived {
                f[j].revived = true
                f[j].hp = f[j].maxHP * (f[j].p.todayE[1] >= 0.9 ? 0.4 : 0.2)
                say("🛌 " + t("\(names[j]) got back up with Deep Sleep!", "\(names[j]) 发动「深度睡眠」，重新站了起来！"))
                return false
            }
            return true
        }

        var i = f[0].spd == f[1].spd ? r.int(2) : (f[0].spd > f[1].spd ? 0 : 1)
        var over = false
        for _ in 0..<40 where !over {
            let j = 1 - i
            defer { i = 1 - i }
            if f[i].burn > 0 {
                f[i].burn -= 1
                let b = f[i].maxHP * 0.06
                f[i].hp -= b
                say("♨️ " + t("\(names[i]) is burning: \(Int(b.rounded())) damage", "\(names[i]) 被烧伤，掉了 \(Int(b.rounded())) 点体力"))
                if down(i) { over = true; continue }
            }
            if f[i].bound {
                f[i].bound = false
                if r.double() < 0.6 { say("🌿 " + t("\(names[i]) is tangled in vines and can't move", "\(names[i]) 被藤蔓缠住，动不了")); continue }
            }
            if f[i].para > 0 {
                f[i].para -= 1
                if r.double() < 0.3 { say("🌀 " + t("\(names[i]) is jolted stiff", "\(names[i]) 被麻痹了，动不了")); continue }
            }
            if r.double() < f[i].yawn {
                if f[i].has("nap"), let basic = f[i].p.skills.first {
                    say("😴 " + t("\(names[i]) yawned… and turned it into a Nap Counter!", "\(names[i]) 打了个哈欠……发动「午睡反击」！"))
                    _ = hit(i, 1.2, basic)
                    if down(j) { over = true }
                } else {
                    say("😪 " + t("\(names[i]) yawned and skipped a turn", "\(names[i]) 犯困，打了个哈欠"))
                }
                continue
            }
            // choose a skill: heal when low, sometimes a status move, otherwise the strongest attack
            let act = f[i].p.skills.filter { $0.kind != .passive }
            let sun = f[i].p.todayE[0], water = f[i].p.todayE[1]
            let limit: [SkillKind: Int] = [.paralyze: 1, .bind: 2, .burn: 2, .shield: 2]
            func pick(_ k: SkillKind) -> Skill? {
                act.first { $0.kind == k && (f[i].uses[$0.id] ?? 0) < (limit[k] ?? 99) }
            }
            func use(_ sk: Skill) { f[i].uses[sk.id, default: 0] += 1 }
            if f[i].hp < 0.4 * f[i].maxHP, f[i].heals < 2, let h = pick(.heal) {
                let amt = f[i].maxHP * min(0.3, h.power + (h.id == "drizzle" ? 0.15 * water : 0.2 * sun))
                f[i].hp = min(f[i].maxHP, f[i].hp + amt)
                f[i].heals += 1
                say("\(h.emoji) " + t("\(names[i]) used \(h.name(lang)) and healed \(Int(amt.rounded()))", "\(names[i]) 使出「\(h.name(lang))」，回复 \(Int(amt.rounded())) 点体力"))
                continue
            }
            if let b = pick(.burn), f[j].burn == 0, r.double() < 0.45 {
                use(b)
                f[j].burn = 3
                say("\(b.emoji) " + t("\(names[i]) used \(b.name(lang)): \(names[j]) is burning", "\(names[i]) 使出「\(b.name(lang))」，\(names[j]) 烧起来了"))
                continue
            }
            if let b = pick(.bind), !f[j].bound, r.double() < 0.35 {
                use(b)
                f[j].bound = true
                say("\(b.emoji) " + t("\(names[i]) used \(b.name(lang))", "\(names[i]) 使出「\(b.name(lang))」"))
                continue
            }
            if let b = pick(.paralyze), f[j].para == 0, r.double() < 0.4 {
                use(b)
                f[j].para = 3
                say("\(b.emoji) " + t("\(names[i]) used \(b.name(lang)): \(names[j]) is jolted", "\(names[i]) 使出「\(b.name(lang))」，\(names[j]) 被电得发麻"))
                continue
            }
            if let b = pick(.shield), !f[i].shield, r.double() < 0.25 {
                use(b)
                f[i].shield = true
                say("\(b.emoji) " + t("\(names[i]) raised a \(b.name(lang))", "\(names[i]) 张开「\(b.name(lang))」"))
                continue
            }
            let attacks = act.filter { [.attack, .multi, .charge, .recoil].contains($0.kind) }
            func value(_ s: Skill) -> Double { s.kind == .charge ? 1 + 1.5 * sun : s.power * Double(s.hits) }
            let best = attacks.max { value($0) < value($1) } ?? attacks[0]
            let sk = r.double() < 0.7 ? best : r.pick(attacks)
            switch sk.kind {
            case .charge: _ = hit(i, 1 + 1.5 * sun, sk)
            case .multi: for _ in 0..<sk.hits where f[j].hp > 0 { _ = hit(i, sk.power, sk) }
            case .recoil:
                _ = hit(i, sk.power, sk)
                f[i].hp -= f[i].maxHP * 0.08
                if down(i) { over = true; continue }
            default: _ = hit(i, sk.power, sk)
            }
            if down(j) { over = true }
        }
        let w = f[0].hp / f[0].maxHP >= f[1].hp / f[1].maxHP ? 0 : 1
        if log.count > 10 { log = Array(log.prefix(5)) + ["…"] + Array(log.suffix(4)) }
        log.append(t("🏆 \(names[w]) (\(w == 0 ? x.owner : y.owner)) wins!", "🏆 \(names[w])（\(w == 0 ? x.owner : y.owner)）获胜！"))
        return Battle(a: x.owner, b: y.owner, winner: w == 0 ? x.owner : y.owner, log: log)
    }

    /// Season results: pets as of today, with the wins and losses of every day's round-robin so far.
    static func season(_ ledger: Ledger, dates: [String], season: Int, today: String, lang: String) -> (pets: [PetResult], today: [Battle], h2h: [String: [String: Int]]) {
        var wins: [String: Int] = [:], losses: [String: Int] = [:], h2h: [String: [String: Int]] = [:]
        var todays: [Battle] = []
        for d in dates where d <= today {
            let ps = state(ledger, dates: dates, season: season, upTo: d).filter(\.hatched)
            for (i, x) in ps.enumerated() {
                for y in ps[(i + 1)...] {
                    let b = battle(x, y, day: d, lang: lang)
                    let loser = b.winner == x.owner ? y.owner : x.owner
                    wins[b.winner, default: 0] += 1
                    losses[loser, default: 0] += 1
                    h2h[b.winner, default: [:]][loser, default: 0] += 1
                    if d == today { todays.append(b) }
                }
            }
        }
        var pets = state(ledger, dates: dates, season: season, upTo: today)
        for k in pets.indices { pets[k].wins = wins[pets[k].owner] ?? 0; pets[k].losses = losses[pets[k].owner] ?? 0 }
        pets.sort { ($0.wins, $0.exp) != ($1.wins, $1.exp) ? ($0.wins, $0.exp) > ($1.wins, $1.exp) : $0.owner < $1.owner }
        return (pets, todays, h2h)
    }

    // MARK: drawing (original designs)

    static func petSVG(_ p: PetResult) -> String {
        let pet = p.pet, el = pet.element
        var s = #"<svg viewBox="0 0 160 150" class="pet" aria-hidden="true"><ellipse cx="80" cy="140" rx="44" ry="6" class="shadow"/>"#
        if !p.hatched {
            // egg, cracking as it gets close to hatching
            // every egg looks the same, so nothing about what hatches is given away
            s += ##"<g class="egg"><path d="M80 22 C112 22 126 70 124 98 C122 126 104 138 80 138 C56 138 38 126 36 98 C34 70 48 22 80 22 Z" fill="#fdf6ec" stroke="#b89f7e" stroke-width="2"/>"##
            for (x, y, rr) in [(62.0, 64.0, 8.0), (96, 52, 6), (100, 96, 9), (66, 108, 6)] { s += ##"<circle cx="\##(x)" cy="\##(y)" r="\##(rr)" fill="#e6d3b3"/>"## }
            if p.exp >= PetResult.hatchAt * 0.6 { s += ##"<path d="M56 80 l10 -8 l8 9 l9 -10 l8 8 l9 -7" stroke="#8a6f4e" stroke-width="2" fill="none" stroke-linejoin="round"/>"## }
            return s + "</g></svg>"
        }
        let k = [0, 0.72, 0.86, 1.0][p.stage]
        if pet.species == 2 {
            s += ##"<defs><linearGradient id="rb-\##(uid(pet.owner))" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ff9a9e"/><stop offset=".35" stop-color="#fad0c4"/><stop offset=".6" stop-color="#a1c4fd"/><stop offset="1" stop-color="#c2e9fb"/></linearGradient></defs>"##
        }
        if pet.rarity >= 2 { s += #"<circle cx="80" cy="88" r="66" fill="\#(Rarity.colors[pet.rarity])" opacity=".12"/>"# }
        s += #"<g transform="translate(80 140) scale(\#(k)) translate(-80 -140)"><g class="bob">"#
        let stroke = pet.shiny || pet.rarity == 3 ? "#d4a017" : pet.species == 1 ? "#141c3a" : el.dark
        // tail
        if pet.tail == 1 { s += #"<path d="M130 126 q14 0 14 -10 q0 -8 -7 -7 q-5 1 -3 6" stroke="\#(stroke)" stroke-width="4" fill="none" stroke-linecap="round"/>"# }
        if pet.tail == 2 { s += #"<circle cx="134" cy="112" r="13" fill="\#(el.belly)" stroke="\#(stroke)" stroke-width="1.5"/>"# }
        // ears
        switch pet.ears {
        case 0: s += #"<circle cx="48" cy="44" r="14" fill="\#(pet.body)" stroke="\#(stroke)" stroke-width="2"/><circle cx="112" cy="44" r="14" fill="\#(pet.body)" stroke="\#(stroke)" stroke-width="2"/>"#
        case 1: s += #"<path d="M40 60 L50 22 L70 44 Z M120 60 L110 22 L90 44 Z" fill="\#(pet.body)" stroke="\#(stroke)" stroke-width="2" stroke-linejoin="round"/>"#
        case 2: s += #"<ellipse cx="54" cy="36" rx="9" ry="24" transform="rotate(-18 54 36)" fill="\#(pet.body)" stroke="\#(stroke)" stroke-width="2"/><ellipse cx="106" cy="36" rx="9" ry="24" transform="rotate(18 106 36)" fill="\#(pet.body)" stroke="\#(stroke)" stroke-width="2"/>"#
        default: s += #"<path d="M50 46 q-6 -16 4 -20 q2 10 8 12 M110 46 q6 -16 -4 -20 q-2 10 -8 12" fill="\#(pet.body)" stroke="\#(stroke)" stroke-width="2"/>"#
        }
        // body
        s += #"<path d="M80 34 C122 34 138 70 134 100 C130 128 110 138 80 138 C50 138 30 128 26 100 C22 70 38 34 80 34 Z" fill="\#(pet.body)" stroke="\#(stroke)" stroke-width="2.5"/>"#
        switch pet.pattern {
        case 1: for (x, y) in [(46.0, 84.0), (114, 78), (104, 116)] { s += #"<circle cx="\#(x)" cy="\#(y)" r="6" fill="\#(el.dark)" opacity=".22"/>"# }
        case 2: s += #"<path d="M66 40 q4 8 0 14 M80 37 q4 9 0 16 M94 40 q4 8 0 14" stroke="\#(el.dark)" stroke-width="3" opacity=".3" fill="none" stroke-linecap="round"/>"#
        case 3: s += #"<ellipse cx="80" cy="112" rx="30" ry="22" fill="\#(el.belly)"/>"#
        default: break
        }
        if pet.species == 1 {  // starry puff: stars on a night-sky body
            for (x, y, rr) in [(50.0, 70.0, 1.8), (108, 64, 2.2), (60, 118, 1.6), (112, 108, 2), (90, 126, 1.4), (40, 100, 1.5)] {
                s += ##"<circle cx="\##(x)" cy="\##(y)" r="\##(rr)" fill="#fff6c2"/>"##
            }
        }
        // crest on the forehead shows the element
        switch el {
        case .water: s += #"<path d="M80 40 C86 50 88 54 88 58 a8 8 0 0 1 -16 0 C72 54 74 50 80 40 Z" fill="\#(el.dark)" opacity=".85"/>"#
        case .fire: s += #"<path d="M80 38 C90 48 90 56 86 62 C84 56 82 54 80 52 C78 56 76 58 74 62 C70 54 72 46 80 38 Z" fill="\#(el.dark)" opacity=".85"/>"#
        case .leaf: s += #"<path d="M72 60 C72 46 82 40 90 40 C90 52 84 60 72 60 Z" fill="\#(el.dark)" opacity=".85"/>"#
        case .spark: s += #"<path d="M84 38 L74 54 L81 54 L76 66 L88 50 L81 50 Z" fill="\#(el.dark)" opacity=".85"/>"#
        }
        // face
        switch pet.eyes {
        case 0: s += ##"<circle cx="64" cy="84" r="5" fill="#2b2b2b"/><circle cx="96" cy="84" r="5" fill="#2b2b2b"/><circle cx="66" cy="82" r="1.6" fill="#fff"/><circle cx="98" cy="82" r="1.6" fill="#fff"/>"##
        case 1: s += ##"<ellipse cx="64" cy="84" rx="7" ry="8" fill="#2b2b2b"/><ellipse cx="96" cy="84" rx="7" ry="8" fill="#2b2b2b"/><circle cx="67" cy="81" r="2.6" fill="#fff"/><circle cx="99" cy="81" r="2.6" fill="#fff"/><circle cx="62" cy="88" r="1.2" fill="#fff"/><circle cx="94" cy="88" r="1.2" fill="#fff"/>"##
        default: s += ##"<path d="M57 86 q7 -8 14 0 M89 86 q7 -8 14 0" stroke="#2b2b2b" stroke-width="3" fill="none" stroke-linecap="round"/>"##
        }
        if pet.species == 1 {  // the dark body needs light eye rims
            s += ##"<circle cx="64" cy="84" r="8.5" fill="none" stroke="#fff6c2" stroke-width="1.2" opacity=".7"/><circle cx="96" cy="84" r="8.5" fill="none" stroke="#fff6c2" stroke-width="1.2" opacity=".7"/>"##
        }
        s += ##"<ellipse cx="52" cy="98" rx="7" ry="4" fill="#ff8fa3" opacity=".45"/><ellipse cx="108" cy="98" rx="7" ry="4" fill="#ff8fa3" opacity=".45"/>"##
        s += ##"<path d="M74 98 q3 4 6 0 q3 4 6 0" stroke="#2b2b2b" stroke-width="2" fill="none" stroke-linecap="round"/>"##
        if p.condition.sleepy { s += #"<text x="20" y="58" font-size="16">💤</text>"# }
        s += #"<ellipse cx="62" cy="138" rx="11" ry="5" fill="\#(pet.body)" stroke="\#(stroke)" stroke-width="2"/><ellipse cx="98" cy="138" rx="11" ry="5" fill="\#(pet.body)" stroke="\#(stroke)" stroke-width="2"/>"#
        if pet.rarity == 3 { s += ##"<ellipse cx="80" cy="22" rx="22" ry="5" fill="none" stroke="#f4c430" stroke-width="3"/>"## }  // halo
        if pet.rarity == 1 { s += ##"<text x="116" y="40" font-size="14">⭐</text>"## }
        if pet.shiny { s += #"<text x="24" y="40" font-size="16">✨</text><text x="128" y="128" font-size="12">✨</text>"# }
        return s + "</g></g></svg>"
    }

    // MARK: page

    static func render(_ ledger: Ledger, cfg: Config, today: String, now: Date) -> String {
        let lang = cfg.language == "zh" ? "zh" : "en"
        func t(_ en: String, _ zh: String) -> String { lang == "zh" ? zh : en }
        let (index, dates) = Garden.season(ledger, start: cfg.gardenStart, length: cfg.gardenDays, today: today)
        let day = (dates.firstIndex(of: today) ?? 0) + 1
        let (pets, battles, h2h) = season(ledger, dates: dates, season: index, today: today, lang: lang)
        let time = now.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: lang == "zh" ? "zh_CN" : "en_US")))
        let medals = ["🥇", "🥈", "🥉"]
        var h = """
        <!doctype html>
        <html lang="\(lang == "zh" ? "zh-CN" : "en")"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(t("Puff Battles", "团团对战"))</title>
        <style>\(Garden.css)\(css)</style></head><body><main>
        <header><h1>🥚 \(t("Puff Battles", "团团对战"))</h1>
        <p class="sub">\(t("Season \(index) · day \(day) of \(dates.count)", "第 \(index) 季 · 第 \(day) / \(dates.count) 天")) · \(t("updated", "更新于")) \(Garden.esc(time))</p></header>
        """
        if pets.isEmpty {
            h += "<p class=\"empty\">\(t("No one has data yet. Files named health-<name>.txt in the shared HealthGlance folder join the game.", "还没有人有数据。共享文件夹 HealthGlance 里的 health-名字.txt 会自动加入。"))</p>"
        }
        h += "<section class=\"board\">"
        for (i, p) in pets.enumerated() {
            h += """
            <div class="rank"><span class="medal">\(i < 3 ? medals[i] : "\(i + 1)")</span><span class="who">\(Garden.esc(p.owner))</span>\
            <span class="pe">\(p.hatched ? p.pet.element.emoji : "🥚")</span><span class="pts">\(p.wins)<small> \(t("W", "胜")) · \(p.losses) \(t("L", "负"))</small></span>\
            <span class="stg">\(p.hatched ? "Lv \(p.level)" : stageName(0, lang))</span></div>
            """
        }
        h += "</section><section class=\"field\">"
        let maxStat = pets.map { max($0.stats.hp / 4, $0.stats.atk, $0.stats.def, $0.stats.spd) }.max() ?? 1
        for p in pets {
            var tags: [String] = []
            if !p.hasToday { tags.append("🏜️ " + t("No data yet today: a little sluggish", "今天还没有数据：没精神")) }
            if p.condition.sleepy { tags.append("😪 " + t("Sleepy: short sleep, slower and may yawn", "犯困：睡得少，速度变慢，可能打哈欠")) }
            if p.condition.pumped { tags.append("💪 " + t("Pumped: 10k steps, +15% attack", "兴奋：走满 1 万步，攻击 +15%")) }
            if p.condition.focused { tags.append("🎯 " + t("Focused: calm heart, more critical hits", "专注：心率平稳，更容易暴击")) }
            if p.condition.energetic { tags.append("⚡ " + t("Energetic: +10% speed", "活力：速度 +10%")) }
            if p.pet.shiny { tags.append("✨ " + t("Shiny! (1 in 20)", "闪光！（1/20 的概率）")) }
            let nextExp = p.hatched ? PetResult.hatchAt + Double(p.level) * 7 : PetResult.hatchAt
            let prevExp = p.hatched ? PetResult.hatchAt + Double(p.level - 1) * 7 : 0
            let prog = min(1, max(0, (p.exp - prevExp) / (nextExp - prevExp)))
            h += """
            <article class="plot"><div class="ph"><b>\(Garden.esc(p.owner))</b><span>\(p.hatched ? "\(p.pet.element.emoji) \(Garden.esc(p.pet.name(lang)))" : "🥚 " + t("Egg", "蛋"))</span></div>
            \(p.hatched ? "<span class=\"rar\" style=\"background:\(Rarity.colors[p.pet.rarity])\">\(Rarity.name(p.pet.rarity, lang))\(p.pet.shiny ? " · " + t("Shiny", "闪光") : "")</span>" : "")
            \(petSVG(p))
            <div class="stage"><b>\(p.hatched ? "\(stageName(p.stage, lang)) · Lv \(p.level)" : t("Hatching…", "孵化中…"))</b><span>\(Int(p.exp.rounded())) EXP · \(p.hatched ? t("next level at \(Int(nextExp))", "下一级 \(Int(nextExp))") : t("hatches at \(Int(PetResult.hatchAt))", "\(Int(PetResult.hatchAt)) 孵化"))</span></div>
            <div class="bar"><i style="width:\(Int(prog * 100))%"></i></div>
            """
            if p.hatched {
                h += "<ul class=\"el\">"
                let rows: [(String, String, Double, Double)] = [
                    ("❤️", t("HP", "体力"), p.stats.hp, p.stats.hp / 4), ("⚔️", t("Attack", "攻击"), p.stats.atk, p.stats.atk),
                    ("🛡️", t("Defense", "防御"), p.stats.def, p.stats.def), ("💨", t("Speed", "速度"), p.stats.spd, p.stats.spd)]
                for (e, n, v, scaled) in rows {
                    h += "<li><span class=\"en\">\(e) \(n)</span><span class=\"eb\"><i style=\"width:\(Int(min(100, scaled / maxStat * 100)))%\"></i></span><span class=\"ev\">\(Int(v.rounded()))</span></li>"
                }
                h += "</ul><ul class=\"sk\">"
                let known = Set(p.skills.map(\.id))
                let listed = Skill.elementSkills[p.pet.element.rawValue].compactMap { Skill.byID[$0] } + p.pet.extra.compactMap { Skill.byID[$0] }
                for sk in listed {
                    let on = known.contains(sk.id)
                    h += "<li class=\"\(on ? "" : "locked")\"><b style=\"color:\(sk.tier > 0 ? Rarity.colors[sk.tier] : "inherit")\">\(sk.emoji) \(Garden.esc(sk.name(lang)))</b>"
                        + "<span>\(on ? Garden.esc(sk.desc(lang)) : t("Unlocks at Lv \(sk.unlock)", "Lv \(sk.unlock) 解锁"))</span></li>"
                }
                h += "</ul>"
            } else {
                h += "<p class=\"hint\">\(t("Every healthy day brings it closer to hatching. What hatches is a surprise.", "每个健康的日子都让它更快孵化，孵出什么是个惊喜。"))</p>"
            }
            if !tags.isEmpty { h += "<p class=\"tags\">" + tags.map { "<span>\(Garden.esc($0))</span>" }.joined() + "</p>" }
            h += "</article>"
        }
        h += "</section>"
        if !battles.isEmpty {
            h += "<section class=\"report\"><h2>⚔️ \(t("Today's battles", "今日对战"))</h2>"
            for b in battles {
                h += "<details class=\"fight\"><summary>\(Garden.esc(b.a)) vs \(Garden.esc(b.b)) — \(t("winner", "胜者")): <b>\(Garden.esc(b.winner))</b></summary><ol>" +
                    b.log.map { "<li>\(Garden.esc($0))</li>" }.joined() + "</ol></details>"
            }
            h += "</section>"
        } else if pets.contains(where: \.hatched) {
            h += "<section class=\"report\"><h2>⚔️ \(t("Today's battles", "今日对战"))</h2><p>\(t("Battles start once at least two pets have hatched.", "至少两只团团孵化后开始对战。"))</p></section>"
        }
        let hatched = pets.filter(\.hatched)
        if hatched.count >= 2 {
            h += "<section class=\"report\"><h2>🤝 \(t("Head to head this season", "本季交手记录"))</h2><table class=\"h2h\"><tr><th></th>" + hatched.map { "<th>\(Garden.esc($0.owner))</th>" }.joined() + "</tr>"
            for a in hatched {
                h += "<tr><th>\(Garden.esc(a.owner))</th>" + hatched.map { b in a.owner == b.owner ? "<td>—</td>" : "<td>\(h2h[a.owner]?[b.owner] ?? 0) : \(h2h[b.owner]?[a.owner] ?? 0)</td>" }.joined() + "</tr>"
            }
            h += "</table></section>"
        }
        // rules
        h += "<details><summary>\(t("How it works", "规则"))</summary><div class=\"rules\">"
        h += "<p>\(t("At the start of each season everyone gets an egg. What hatches is random: element, colour, ears, pattern, tail and eyes, with a 1 in 20 chance of a shiny.", "每一季开始时，每人领到一颗蛋。孵出什么是随机的：属性、颜色、耳朵、花纹、尾巴和眼睛都不一样，还有 1/20 的概率孵出闪光团团。"))</p>"
        h += "<p>\(t("Each day's Health numbers feed your pet. The day's growth points (up to 10, plus 1 for a 3-day streak) are EXP: the egg hatches at 15 EXP, and every 7 EXP after that is a level. Each element also trains one stat:", "每天的健康数据就是它的口粮。当天的成长分（最多 10 分，连续 3 天达标再加 1 分）就是经验值：15 点经验孵化，之后每 7 点升一级。每种要素还会训练一项属性："))</p><ul>"
        h += "<li>☀️ \(t("Steps → Attack", "步数 → 攻击"))</li><li>💧 \(t("Sleep → HP", "睡眠 → 体力"))</li><li>🍃 \(t("Calm resting heart rate → Defense", "静息心率平稳 → 防御"))</li><li>🌱 \(t("Active energy or exercise → Speed", "活动能量或锻炼 → 速度"))</li></ul>"
        h += "<p>\(t("Every day, each hatched pet battles every other one once. The faster pet moves first. Elements: 💧 Water beats 🔥 Fire, 🔥 Fire beats 🍃 Leaf, 🍃 Leaf beats ⚡ Spark, ⚡ Spark beats 💧 Water (×1.5 damage; ×0.7 the other way).", "每天，每只孵化的团团都和其他每一只对战一次，速度快的先出手。属性克制：💧 水克 🔥 火，🔥 火克 🍃 叶，🍃 叶克 ⚡ 电，⚡ 电克 💧 水（克制时伤害 ×1.5，被克时 ×0.7）。"))</p>"
        h += "<p>\(t("Today's numbers set today's mood: under about 6 h of sleep makes it sleepy (slower, may yawn), 10,000 steps makes it pumped (+15% attack), a calm heart makes it focused (more critical hits), and no data yet makes it sluggish (−10%).", "今天的数据决定今天的状态：睡不到约 6 小时会犯困（变慢，可能打哈欠），走满 1 万步会兴奋（攻击 +15%），心率平稳会专注（更容易暴击），还没有数据会没精神（全部 −10%）。"))</p>"
        h += "<p>\(t("Rarity is rolled at hatching. Rarer pets get a few % more stats and extra skills:", "稀有度在孵化时抽取。越稀有，属性略高几个百分点，并多带技能："))</p><table><tr><th>\(t("Rarity", "稀有度"))</th><th>\(t("Odds", "概率"))</th><th>\(t("Extra", "额外"))</th></tr>"
        let extras = [t("—", "—"), t("1 rare skill, +2%", "1 个稀有技能，属性 +2%"), t("1 rare + 1 epic skill, +4%", "稀有和史诗技能各 1 个，属性 +4%"), t("Starry or Rainbow Puff with its own skill, plus rare and epic skills, +6%", "星空团或彩虹团，带专属技能，另有稀有、史诗技能各 1 个，属性 +6%")]
        for k in 0..<4 { h += "<tr><td style=\"color:\(Rarity.colors[k])\"><b>\(Rarity.name(k, lang))</b></td><td>\(Rarity.odds[k])%</td><td>\(extras[k])</td></tr>" }
        h += "</table><p>\(t("Skills", "技能"))</p><table><tr><th>\(t("Skill", "技能"))</th><th>\(t("Who", "谁会"))</th><th>\(t("Effect", "效果"))</th></tr>"
        for sk in Skill.all {
            let who = sk.tier == 0 ? "\(PetElement(rawValue: Skill.elementSkills.firstIndex { $0.contains(sk.id) } ?? 0)!.emoji) Lv \(sk.unlock)" : Rarity.name(sk.tier, lang)
            h += "<tr><td style=\"color:\(sk.tier > 0 ? Rarity.colors[sk.tier] : "inherit")\">\(sk.emoji) \(Garden.esc(sk.name(lang)))</td><td>\(who)</td><td>\(Garden.esc(sk.desc(lang)))</td></tr>"
        }
        h += "</table>"
        h += "<p>\(t("The most wins at the end of the season takes the title; ties go to the higher EXP. Pets and battles are worked out from names and dates, so the page gives the same result every time it is made.", "季末胜场最多的人夺冠，胜场相同比经验值。团团和对战结果都由名字和日期算出，每次生成页面结果都一样。"))</p></div></details>"
        h += "<footer>\(t("Numbers come from each player's own Health app. Page made by \(Garden.esc(cfg.gardenName))'s Mac with HealthGlance. Not medical advice.", "数据来自每个人自己的「健康」App。页面由 \(Garden.esc(cfg.gardenName)) 的 Mac 用 HealthGlance 生成。不构成医疗建议。"))</footer>"
        return h + "</main></body></html>\n"
    }

    static let css = """
    .pet{display:block;width:100%;height:160px;margin:2px 0}.shadow{fill:var(--line)}
    .hint{color:var(--sub);font-size:13px;margin:4px 0 0}
    .rar{display:inline-block;color:#fff;font-size:11px;font-weight:700;border-radius:8px;padding:1px 8px;margin-top:4px}
    .sk{list-style:none;margin:10px 0 0;padding:0;display:grid;gap:4px;font-size:12px}.sk li{display:grid;grid-template-columns:auto 1fr;gap:8px}.sk span{color:var(--sub)}.sk li.locked{opacity:.45}
    .fight{margin:8px 0 0;padding:8px 12px}.fight ol{margin:8px 0 2px;padding-left:20px;font-size:13px;color:var(--sub)}.fight ol li:last-child{color:var(--ink);font-weight:600;list-style:none;margin-left:-20px}
    .h2h{border-collapse:collapse;font-size:13px}.h2h th,.h2h td{padding:5px 10px;border-bottom:1px solid var(--line);text-align:center}.h2h th:first-child{text-align:left}
    @keyframes bob{0%,100%{transform:translateY(0)}50%{transform:translateY(-3px)}}@keyframes wob{0%,100%{transform:rotate(0)}25%{transform:rotate(-3deg)}75%{transform:rotate(3deg)}}
    .egg{transform-origin:80px 138px;animation:wob 2.4s ease-in-out infinite}.pet>.bob{animation:bob 2.2s ease-in-out infinite}
    """
}
