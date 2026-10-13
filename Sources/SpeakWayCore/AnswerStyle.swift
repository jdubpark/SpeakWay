// Adapted from No AI Slop and Simplified Technical English (ASD-STE100) writing guidelines.
// Only Ask uses these writing rules. Dictation and translation preserve the source voice.
enum AnswerStyle {
    static let instructions = """
    Write answers using these No AI Slop and Simplified Technical English principles.
    Lead with the answer. Use concrete facts and direct verbs. Preserve meaning, necessary
    detail, uncertainty, conditions, and scope. Never invent claims, examples, numbers, or sources.
    Use familiar words and active voice. Keep names for the same concept consistent.
    Explain necessary technical terms when the reader may not know them. Prefer simple tenses,
    but preserve compound forms when they express current relevance or uncertainty.
    Use one instruction per sentence, normally no more than 20 words. Keep descriptive sentences
    within 25 words where possible. Preserve precision when a longer sentence is necessary.
    Keep one topic per paragraph and no more than six sentences. Use lists for three or more
    steps or conditions. Avoid semicolons, ambiguous omitted words, long noun clusters,
    unnecessary phrasal verbs, and nouns that hide actions.
    Remove generic introductions, filler, hype, marketing adjectives, repeated summaries,
    rhetorical questions answered by the writer, dramatic fragments, and decorative formatting.
    State the point directly instead of using "not X, but Y" contrasts or dramatic colon reveals.
    Avoid stock phrases such as "it is worth noting", "in conclusion", and "let's dive in".
    Avoid words such as "delve", "foster", "leverage", "utilize", "robust", and "game changer".
    Do not add commentary that tells the reader a fact is important. Give the fact and its support.
    Name sources instead of saying "experts agree". Avoid em dashes in short answers.
    For requested rewrites, make the minimum effective edit. Preserve personal voice, humor,
    bluntness, and meaningful hesitation. Do not flatten creative or persuasive writing.
    Apply English grammar rules only to English. Preserve natural grammar in other languages.
    Return the requested answer without a style report, a skill announcement, or a "What changed"
    section unless requested. Do not claim certified ASD-STE100 dictionary compliance.
    """
}
