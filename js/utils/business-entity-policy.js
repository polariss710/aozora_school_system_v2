export const PRIMARY_SCHOOL_BUSINESS_ENTITY_CODE = "aosora";

export function isPrimarySchoolBusinessEntity(entity) {
  return Boolean(
    entity?.id &&
    entity?.code === PRIMARY_SCHOOL_BUSINESS_ENTITY_CODE
  );
}

export function primarySchoolBusinessEntity(entities = []) {
  return (entities || []).find(isPrimarySchoolBusinessEntity) || null;
}

export function newBusinessEntities(entities = []) {
  return (entities || []).filter((entity) => (
    entity?.id &&
    entity.is_active !== false &&
    isPrimarySchoolBusinessEntity(entity)
  ));
}

export function defaultNewBusinessEntityId(entities = []) {
  return primarySchoolBusinessEntity(entities)?.id || "";
}

export function historicalEditBusinessEntities(entities = [], currentId = "") {
  const rowsById = new Map();
  for (const entity of newBusinessEntities(entities)) {
    rowsById.set(entity.id, entity);
  }
  const current = (entities || []).find((entity) => entity?.id === currentId);
  if (current?.id) {
    rowsById.set(current.id, current);
  }
  return Array.from(rowsById.values());
}

export function isNewBusinessEntityId(entities = [], entityId = "") {
  return Boolean(entityId && newBusinessEntities(entities).some((entity) => entity.id === entityId));
}
