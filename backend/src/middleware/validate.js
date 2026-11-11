import { HttpError } from '../errors.js';

/**
 * Checks req.body against a zod schema. On failure it answers 422 with one
 * message per field, which the app shows under the matching text box.
 */
export const validateBody = (schema) => (req, res, next) => {
  const result = schema.safeParse(req.body ?? {});
  if (!result.success) {
    const fields = {};
    for (const issue of result.error.issues) {
      const key = issue.path.join('.') || '_';
      fields[key] ??= issue.message;
    }
    throw new HttpError(422, 'Please check the highlighted fields.', fields);
  }
  req.body = result.data;
  next();
};
