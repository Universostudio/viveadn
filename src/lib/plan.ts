// La base rechaza el alta que supera el tope del plan con un error cuyo mensaje empieza por PLAN_LIMITE
export const esLimitePlan = (err: unknown): boolean => /PLAN_LIMITE/.test(String((err as { message?: unknown } | null)?.message ?? ''))
