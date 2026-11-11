/** An error with an HTTP status that is safe to show to the user. */
export class HttpError extends Error {
  constructor(status, message, fields) {
    super(message);
    this.status = status;
    this.fields = fields; // { email: 'Already registered' } for form errors
  }
}

export function notFound(req, res) {
  res.status(404).json({ error: `No route for ${req.method} ${req.path}` });
}

// Express 5 forwards errors thrown in async handlers here automatically.
// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, next) {
  if (err instanceof HttpError) {
    return res.status(err.status).json({ error: err.message, fields: err.fields });
  }
  if (err.name === 'MulterError') {
    const tooBig = err.code === 'LIMIT_FILE_SIZE';
    return res.status(tooBig ? 413 : 400).json({
      error: tooBig ? 'Photo is too large. The limit is 5 MB.' : 'Upload one photo in a field called "photo".',
    });
  }
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'Request body is not valid JSON.' });
  }
  console.error(err);
  res.status(500).json({ error: 'Something went wrong on the server.' });
}
