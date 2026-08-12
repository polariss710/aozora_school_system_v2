const LESSON_CANCELLATION_ROLES = new Set(["admin", "operator"]);

export function isActiveLessonCancellationActor(authContext) {
  const membership = authContext?.membership;
  return membership?.is_active === true && LESSON_CANCELLATION_ROLES.has(membership.role);
}

export function canShowPlannedCancellationAction({
  authContext,
  planned,
  hasLinkedActual = false,
} = {}) {
  return isActiveLessonCancellationActor(authContext)
    && planned?.lesson_type === "planned"
    && planned.status === "planned"
    && !planned.voided_at
    && hasLinkedActual !== true;
}
