import SwiftUI

/// Production swap point: replace the mock implementation with a networked strategist that returns the same `AskTaiResponse` shape.
protocol AskTaiGuidanceService {
    func response(for prompt: String) -> AskTaiResponse
}

struct MockAskTaiGuidanceService: AskTaiGuidanceService {
    func response(for prompt: String) -> AskTaiResponse {
        AskTaiMockStrategistEngine.buildResponse(for: prompt)
    }
}

struct AskTaiPromptPreset: Identifiable {
    let id: String
    let title: String
    let text: String
    let icon: String
    let tint: Color

    static let defaultPrompts: [AskTaiPromptPreset] = [
        AskTaiPromptPreset(
            id: "protein-dinner",
            title: "Dinner move",
            text: "Plan a high-protein dinner from my remaining macros",
            icon: "fork.knife.circle.fill",
            tint: .mint
        ),
        AskTaiPromptPreset(
            id: "social",
            title: "Social plan",
            text: "How do I stay on track for drinks tonight?",
            icon: "wineglass.fill",
            tint: .purple
        ),
        AskTaiPromptPreset(
            id: "grocery",
            title: "Grocery sprint",
            text: "Give me a fast grocery strategy for tomorrow",
            icon: "cart.fill",
            tint: .blue
        ),
        AskTaiPromptPreset(
            id: "prep",
            title: "Prep now",
            text: "What should I prep now so evening decisions are easy?",
            icon: "takeoutbag.and.cup.and.straw.fill",
            tint: .orange
        )
    ]
}

struct AskTaiResponse: Identifiable {
    let id: String
    let prompt: String
    let summary: String
    let recommendations: [AskTaiRecommendation]
    let fallbackCoaching: String
    let followUps: [AskTaiFollowUpChip]
}

struct AskTaiRecommendation: Identifiable {
    let id: String
    let title: String
    let whyItFits: String
    let context: String
    let macroHint: String
    let icon: String
}

struct AskTaiFollowUpChip: Identifiable {
    let id: String
    let label: String
    let prompt: String
}

enum AskTaiMockStrategistEngine {
    static func buildResponse(for prompt: String) -> AskTaiResponse {
        let normalized = prompt.lowercased()
        let hasCarbs = normalized.contains("carb")
        let hasDrinks = normalized.contains("drink")
        let hasDinner = normalized.contains("dinner")
        let hasProtein = normalized.contains("protein")
        let hasTakeaway = normalized.contains("takeaway") || normalized.contains("take away")
        let hasWeekend = normalized.contains("weekend")

        var summary = "Tonight, lean into carbs and protein at dinner so drinks fit without pushing the week off track."
        var fallback = "If dinner changes, anchor protein first and keep dessert optional."

        if hasTakeaway {
            summary = "Use takeaway as a controlled choice: lock in protein first, then add carbs based on runway."
            fallback = "If options are limited, pick grilled protein and skip the default sides."
        } else if hasWeekend {
            summary = "Treat this as weekend decision support: bank protein and hydration early so social meals stay flexible."
            fallback = "If plans stack up, keep one meal intentionally lighter before going out."
        } else if hasDrinks {
            summary = "Keep drinks in play by making dinner protein-first with moderate carbs and low friction choices."
        } else if hasDinner && hasProtein {
            summary = "For dinner, prioritize a protein anchor and pair just enough carbs to stay satisfied."
        } else if hasCarbs {
            summary = "Use carbs strategically: pair with lean protein so energy stays steady instead of spiking."
        } else if hasProtein {
            summary = "Prioritize protein in your next meal, then layer carbs based on how active tonight looks."
        }

        let recommendations = recommendationSet(
            hasCarbs: hasCarbs,
            hasDrinks: hasDrinks,
            hasDinner: hasDinner,
            hasProtein: hasProtein,
            hasTakeaway: hasTakeaway,
            hasWeekend: hasWeekend
        )

        let followUps = [
            AskTaiFollowUpChip(id: "more-drinks", label: "What if I drink more?", prompt: "What if I drink more tonight?"),
            AskTaiFollowUpChip(id: "restaurant", label: "Restaurant version", prompt: "Give me a restaurant version of this strategy."),
            AskTaiFollowUpChip(id: "grocery", label: "Grocery version", prompt: "Give me a grocery version I can prep quickly."),
            AskTaiFollowUpChip(id: "takeaway", label: "Fast takeaway", prompt: "Give me a fast takeaway strategy with protein first.")
        ]

        return AskTaiResponse(
            id: prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "empty-prompt" : prompt,
            prompt: prompt,
            summary: summary,
            recommendations: recommendations,
            fallbackCoaching: fallback,
            followUps: followUps
        )
    }

    private static func recommendationSet(
        hasCarbs: Bool,
        hasDrinks: Bool,
        hasDinner: Bool,
        hasProtein: Bool,
        hasTakeaway: Bool,
        hasWeekend: Bool
    ) -> [AskTaiRecommendation] {
        if hasTakeaway {
            return [
                AskTaiRecommendation(
                    id: "takeaway-bowl",
                    title: "Grilled chicken rice bowl",
                    whyItFits: "Protein-forward base with adjustable carbs keeps calories predictable.",
                    context: "Best for fast delivery nights when you need a no-drama order.",
                    macroHint: "Aim extra chicken, half rice if drinks are planned.",
                    icon: "🥗"
                ),
                AskTaiRecommendation(
                    id: "takeaway-sushi",
                    title: "Sushi + edamame",
                    whyItFits: "Lean protein with moderate carbs gives good satiety before social plans.",
                    context: "Works well for dinner out or quick pickup.",
                    macroHint: "Prioritize sashimi/roll balance and skip fried add-ons.",
                    icon: "🍣"
                ),
                AskTaiRecommendation(
                    id: "takeaway-burger",
                    title: "Burger + side salad",
                    whyItFits: "Keeps cravings covered while removing low-value extras.",
                    context: "Useful when everyone wants burgers and you want alignment.",
                    macroHint: "Skip fries, add salad, keep sauces light.",
                    icon: "🍔"
                )
            ]
        }

        if hasWeekend || hasDrinks {
            return [
                AskTaiRecommendation(
                    id: "weekend-bowl",
                    title: "Salmon poke bowl",
                    whyItFits: "Balanced carbs and protein support social flexibility later.",
                    context: "Ideal for early dinner before going out.",
                    macroHint: "Keep creamy toppings minimal; include edamame.",
                    icon: "🐟"
                ),
                AskTaiRecommendation(
                    id: "weekend-taco",
                    title: "Chicken taco plate",
                    whyItFits: "Lets you control portions while still feeling like a weekend meal.",
                    context: "Great at restaurants where everyone orders shared items.",
                    macroHint: "Use corn tortillas, add beans, skip chips.",
                    icon: "🌮"
                ),
                AskTaiRecommendation(
                    id: "weekend-burger",
                    title: "Burger but skip fries",
                    whyItFits: "High satisfaction, less calorie drift, easier to sustain weekly plan.",
                    context: "Best when the social choice is fixed and you need a smart swap.",
                    macroHint: "Add side salad and protein add-on if available.",
                    icon: "🍔"
                )
            ]
        }

        if hasProtein || hasDinner || hasCarbs {
            return [
                AskTaiRecommendation(
                    id: "dinner-rice-bowl",
                    title: "Grilled chicken rice bowl",
                    whyItFits: "Hits protein needs while keeping carbs intentional and simple.",
                    context: "Great for weekday dinner when energy is low.",
                    macroHint: "Double chicken if protein gap is large.",
                    icon: "🍚"
                ),
                AskTaiRecommendation(
                    id: "dinner-sushi",
                    title: "Sushi + edamame",
                    whyItFits: "Clean protein and steady carbs without heavy oils.",
                    context: "Good dine-in or takeaway option with minimal prep.",
                    macroHint: "Favor salmon/tuna + edamame before extra rolls.",
                    icon: "🍣"
                ),
                AskTaiRecommendation(
                    id: "dinner-burger-salad",
                    title: "Burger + side salad",
                    whyItFits: "Keeps dinner satisfying so late snacking is less likely.",
                    context: "Works when home cooking is off the table.",
                    macroHint: "Skip fries and sweet drinks to stay aligned.",
                    icon: "🥬"
                )
            ]
        }

        return [
            AskTaiRecommendation(
                id: "default-bowl",
                title: "Protein bowl",
                whyItFits: "Simple structure gives control without overthinking.",
                context: "Best for busy days when planning time is short.",
                macroHint: "Protein first, carbs second, fats in small additions.",
                icon: "🥣"
            ),
            AskTaiRecommendation(
                id: "default-wrap",
                title: "Turkey wrap + fruit",
                whyItFits: "Portable and balanced with minimal decision fatigue.",
                context: "Good for office or commute nights.",
                macroHint: "Choose whole-grain wrap and lean fillings.",
                icon: "🌯"
            )
        ]
    }
}
