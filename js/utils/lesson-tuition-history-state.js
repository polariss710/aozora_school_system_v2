function unavailableRecord(record) {
  return {
    ...record,
    tuition_history_state_available: false,
    tuition_revision_count: null,
    voided_tuition_revision_count: null,
    active_tuition_revision_count: null,
  };
}

export function mergeLessonTuitionHistoryStates(records, states, readerFailed = false) {
  const sourceRecords = records || [];
  const lessonIds = [...new Set(sourceRecords
    .filter((record) => record.lesson_type === "planned" && record.id)
    .map((record) => record.id))];

  if (!lessonIds.length) {
    return sourceRecords.map((record) => ({
      ...record,
      tuition_history_state_available: true,
    }));
  }
  if (readerFailed) {
    return sourceRecords.map(unavailableRecord);
  }

  const stateByLessonId = new Map((states || []).map((row) => [row.lesson_id, row]));
  if (stateByLessonId.size !== lessonIds.length || lessonIds.some((lessonId) => !stateByLessonId.has(lessonId))) {
    return sourceRecords.map(unavailableRecord);
  }

  return sourceRecords.map((record) => {
    const state = stateByLessonId.get(record.id);
    return {
      ...record,
      tuition_history_state_available: true,
      tuition_revision_count: Number(state?.tuition_revision_count || 0),
      voided_tuition_revision_count: Number(state?.voided_tuition_revision_count || 0),
      active_tuition_revision_count: Number(state?.active_tuition_revision_count || 0),
    };
  });
}

export function mergeLessonTuitionHistoryState(lesson, states, readerFailed = false) {
  return mergeLessonTuitionHistoryStates(lesson ? [lesson] : [], states, readerFailed)[0] || null;
}
