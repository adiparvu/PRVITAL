import Foundation

/// The curated Learn content. Everything here is general, widely-taught diabetes
/// education aligned with mainstream guidance (e.g. the American Diabetes
/// Association Standards of Care and NHS/Diabetes UK patient guidance). It is
/// deliberately conservative and always defers to the user's own care team.
enum LearnLibrary {

    // MARK: Rules

    static let rules: [DiabetesRule] = [
        DiabetesRule(
            id: "rule-of-15",
            title: "The rule of 15",
            tagline: "How to treat a low (hypoglycaemia)",
            symbol: "15.circle.fill",
            steps: [
                "If your glucose is below 70 mg/dL (3.9 mmol/L) and you can safely swallow, take 15 g of fast-acting carbs — for example 4 glucose tablets, 150 ml of regular (non-diet) juice or soda, or 1 tablespoon of sugar or honey.",
                "Wait 15 minutes. Don't eat more straight away, even though you may feel like it.",
                "Recheck your glucose. If it's still below 70 mg/dL, take another 15 g of fast carbs and wait 15 minutes again.",
                "Once you're back above 70 mg/dL, if your next meal is more than an hour away, have a small snack with some longer-lasting carbs and protein to stop the low returning."
            ],
            detail: "Treating with a measured amount and waiting avoids over-treating, which causes a rebound high afterwards. If you ever can't treat yourself, or your glucose stays low, this is an emergency — someone should use glucagon and call emergency services.",
            source: "Aligned with American Diabetes Association and Diabetes UK hypoglycaemia guidance."
        ),
        DiabetesRule(
            id: "prebolus-timing",
            title: "Pre-meal insulin timing",
            tagline: "Giving rapid insulin time to work",
            symbol: "timer",
            steps: [
                "When your glucose is in range before a meal, many people take rapid-acting insulin about 15 minutes before eating so it starts working as the food is digested.",
                "If your pre-meal glucose is higher than target, your team may suggest waiting a little longer before eating so the insulin can catch up.",
                "If your glucose is low or on the way down, treat the low first and take the meal dose after you've started eating.",
                "For very high-fat or high-protein meals, insulin may need to be split or delayed — ask your team how to handle these."
            ],
            detail: "A simple memory aid some clinics teach is to lengthen the wait as your pre-meal number climbs. The exact timing is very individual and depends on your insulin, your meal and how fast you digest — treat this as a starting point to discuss, never a fixed rule.",
            source: "General pre-bolus guidance; personalise timing with your diabetes team."
        ),
        DiabetesRule(
            id: "correcting-a-high",
            title: "Correcting a high safely",
            tagline: "Bringing glucose down without stacking",
            symbol: "arrow.down.right.circle.fill",
            steps: [
                "Check whether you already have active insulin (insulin on board) from a recent dose — Prvital's calculator estimates this — so you don't 'stack' corrections on top of each other.",
                "Use the correction factor agreed with your team, and drink water.",
                "Recheck before correcting again; rapid insulin can keep working for 3–5 hours.",
                "If you have high glucose with ketones, feel unwell, or are vomiting, follow your sick-day plan and contact your care team urgently."
            ],
            detail: "Most rebound lows after a high come from correcting too often. Give a correction time to work before adding more.",
            source: "General correction guidance; use the doses set by your care team."
        ),
        DiabetesRule(
            id: "activity-and-lows",
            title: "Exercise without lows",
            tagline: "Staying steady around activity",
            symbol: "figure.run",
            steps: [
                "Check your glucose before you start. If it's already low or near the bottom of your range, have some carbs first.",
                "Keep fast-acting carbs within reach during activity.",
                "Remember that glucose can keep falling for hours after exercise, including overnight.",
                "Talk to your team about lowering insulin around planned activity rather than only chasing lows with food."
            ],
            detail: "Different activities affect glucose differently — steady cardio often lowers it, while short intense bursts can raise it briefly. Prvital's activity insights help you learn your own pattern.",
            source: "General exercise guidance for people using insulin."
        )
    ]

    // MARK: Encyclopedia

    static let articles: [EncyclopediaArticle] = [
        EncyclopediaArticle(
            id: "time-in-range",
            title: "Time in Range",
            category: .basics,
            summary: "What the green band means and why it matters more than a single number.",
            symbol: "target",
            sections: [
                ArticleSection(heading: "What it is", body: "Time in Range (TIR) is the percentage of the day your glucose sits inside your target band — usually 70–180 mg/dL (3.9–10 mmol/L). It captures both how high and how low you run, which a single average can hide."),
                ArticleSection(heading: "A common goal", body: "A widely-quoted target is to spend around 70% or more of the day in range, with as little time below range as possible. Your personal targets may differ — for example during pregnancy or for young children."),
                ArticleSection(heading: "Why it's useful", body: "More time in range is linked with a lower risk of long-term complications. Because it updates continuously, it's a faster, more actionable feedback loop than an A1c taken every few months.")
            ],
            sources: ["International consensus on Time in Range (Battelino et al., 2019)", "American Diabetes Association Standards of Care"]
        ),
        EncyclopediaArticle(
            id: "estimated-a1c-gmi",
            title: "Estimated A1c (GMI)",
            category: .basics,
            summary: "How your average glucose becomes an A1c-style percentage.",
            symbol: "drop.fill",
            sections: [
                ArticleSection(heading: "What GMI is", body: "The Glucose Management Indicator (GMI) turns your average sensor glucose into a percentage on the same scale as a lab A1c. It's an estimate of where your A1c is likely to land."),
                ArticleSection(heading: "It can differ from lab A1c", body: "GMI and a blood-test A1c won't always match. Red-cell lifespan, anaemia and other factors change lab A1c independently of glucose, so treat GMI as a guide, not a diagnosis."),
                ArticleSection(heading: "Use the trend", body: "The direction of your GMI over weeks is often more useful than any single value.")
            ],
            sources: ["Bergenstal et al., GMI (Diabetes Care, 2018)"]
        ),
        EncyclopediaArticle(
            id: "carb-counting",
            title: "Carb counting basics",
            category: .food,
            summary: "Why carbohydrates drive glucose, and how to estimate them.",
            symbol: "fork.knife",
            sections: [
                ArticleSection(heading: "Carbs matter most", body: "Of the three main nutrients, carbohydrate raises glucose the most and the fastest. Counting the grams of carbohydrate in a meal helps match insulin to food."),
                ArticleSection(heading: "Reading a label", body: "Use the 'total carbohydrate' figure per serving, and check the serving size. Prvital can scan a barcode and calculate the carbs for the exact portion you eat."),
                ArticleSection(heading: "Fibre and net carbs", body: "Fibre is a carbohydrate your body doesn't fully absorb. Some people subtract it to get 'net carbs'. Whether to do this depends on your plan — ask your team."),
                ArticleSection(heading: "Fat and protein", body: "Large amounts of fat and protein can raise glucose later and slow digestion, which is why some meals need a different insulin approach.")
            ],
            sources: ["American Diabetes Association nutrition guidance"]
        ),
        EncyclopediaArticle(
            id: "hypoglycaemia",
            title: "Understanding lows",
            category: .highsAndLows,
            summary: "Spotting and treating hypoglycaemia.",
            symbol: "arrow.down.circle.fill",
            sections: [
                ArticleSection(heading: "What counts as low", body: "A glucose below 70 mg/dL (3.9 mmol/L) is a low. Below 54 mg/dL (3.0 mmol/L) is a serious low that needs immediate treatment."),
                ArticleSection(heading: "Common signs", body: "Shakiness, sweating, hunger, a fast heartbeat, difficulty concentrating, irritability. Some people lose these warning signs over time — talk to your team if that happens to you."),
                ArticleSection(heading: "How to treat it", body: "Follow the rule of 15: 15 g of fast carbs, wait 15 minutes, recheck, repeat if needed. Keep fast carbs and, if prescribed, glucagon within reach.")
            ],
            sources: ["American Diabetes Association hypoglycaemia classification"]
        ),
        EncyclopediaArticle(
            id: "hyperglycaemia",
            title: "Understanding highs",
            category: .highsAndLows,
            summary: "What drives highs and when to worry about ketones.",
            symbol: "arrow.up.circle.fill",
            sections: [
                ArticleSection(heading: "Why glucose rises", body: "Missed or too-little insulin, more carbs than expected, illness, stress and some medicines can all raise glucose. The dawn phenomenon can lift it in the early morning."),
                ArticleSection(heading: "Ketones", body: "If you use insulin and your glucose is high, check for ketones when unwell. High glucose with ketones can lead to diabetic ketoacidosis (DKA), a medical emergency."),
                ArticleSection(heading: "What to do", body: "Correct with the dose your team set, drink water, and follow your sick-day plan. Seek urgent help for high ketones, vomiting or trouble breathing.")
            ],
            sources: ["American Diabetes Association Standards of Care; sick-day guidance"]
        ),
        EncyclopediaArticle(
            id: "dawn-phenomenon",
            title: "The dawn phenomenon",
            category: .highsAndLows,
            summary: "Why glucose often climbs before you wake.",
            symbol: "sunrise.fill",
            sections: [
                ArticleSection(heading: "What happens", body: "In the early hours the body releases hormones that prepare you to wake. These raise glucose, so many people see a rise between roughly 3 and 8 a.m. even without eating."),
                ArticleSection(heading: "What can help", body: "Options your team might discuss include adjusting overnight basal insulin, the timing of evening meals, or activity. Prvital flags a dawn pattern when it sees one so you have data to bring to that conversation.")
            ],
            sources: ["General endocrinology guidance on the dawn phenomenon"]
        )
    ]

    // MARK: Recipes

    static let recipes: [Recipe] = [
        Recipe(
            id: "overnight-oats",
            name: "Berry overnight oats",
            summary: "A make-ahead breakfast with steady, fibre-rich carbs.",
            symbol: "sunrise.fill",
            servings: 1,
            carbsPerServingGrams: 34,
            prepMinutes: 5,
            ingredients: [
                "40 g rolled oats",
                "120 ml unsweetened milk (dairy or soy)",
                "80 g plain Greek yogurt",
                "60 g mixed berries",
                "1 tsp chia seeds",
                "Cinnamon to taste"
            ],
            steps: [
                "Stir the oats, milk, yogurt, chia and cinnamon together in a jar.",
                "Top with the berries.",
                "Cover and chill overnight.",
                "Eat cold, or warm through in the morning."
            ],
            tags: ["High fibre", "Vegetarian", "Make-ahead"]
        ),
        Recipe(
            id: "greek-chicken-salad",
            name: "Greek chicken salad",
            summary: "A low-carb, high-protein lunch that won't spike glucose.",
            symbol: "leaf.fill",
            servings: 2,
            carbsPerServingGrams: 12,
            prepMinutes: 20,
            ingredients: [
                "250 g cooked chicken breast, sliced",
                "1 cucumber, chopped",
                "2 tomatoes, chopped",
                "1/2 red onion, thinly sliced",
                "60 g feta",
                "A handful of olives",
                "Olive oil, lemon juice and oregano"
            ],
            steps: [
                "Combine the cucumber, tomato, onion, olives and feta in a bowl.",
                "Add the chicken.",
                "Dress with olive oil, lemon and oregano, and toss."
            ],
            tags: ["Low carb", "High protein", "Gluten-free"]
        ),
        Recipe(
            id: "veggie-omelette",
            name: "Vegetable omelette",
            summary: "A very low-carb, filling breakfast or quick dinner.",
            symbol: "fork.knife",
            servings: 1,
            carbsPerServingGrams: 6,
            prepMinutes: 10,
            ingredients: [
                "3 eggs",
                "A handful of spinach",
                "50 g mushrooms, sliced",
                "1/4 bell pepper, diced",
                "20 g cheese",
                "Olive oil, salt and pepper"
            ],
            steps: [
                "Soften the mushrooms and pepper in a little oil.",
                "Add the spinach until wilted.",
                "Pour over the beaten eggs, season, and cook until just set.",
                "Add the cheese, fold and serve."
            ],
            tags: ["Low carb", "Vegetarian", "High protein"]
        ),
        Recipe(
            id: "lentil-soup",
            name: "Hearty lentil soup",
            summary: "Fibre-rich lentils give slow, steady carbs.",
            symbol: "takeoutbag.and.cup.and.straw.fill",
            servings: 4,
            carbsPerServingGrams: 30,
            prepMinutes: 40,
            ingredients: [
                "200 g dried lentils, rinsed",
                "1 onion, diced",
                "2 carrots, diced",
                "2 celery sticks, diced",
                "1 tin chopped tomatoes",
                "1 litre vegetable stock",
                "Garlic, cumin, olive oil"
            ],
            steps: [
                "Soften the onion, carrot and celery in olive oil with the garlic and cumin.",
                "Add the lentils, tomatoes and stock.",
                "Simmer for about 30 minutes until the lentils are tender.",
                "Season and serve."
            ],
            tags: ["High fibre", "Vegan", "Batch-cook"]
        )
    ]
}
