import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
} from '@nestjs/common';
import type { Response } from 'express';

/** Prisma/driver errors can contain credential hashes in constraint details.
 * Never serialize or log those exceptions on device credential routes. */
@Catch()
export class DisplayErrorFilter implements ExceptionFilter {
  catch(error: unknown, host: ArgumentsHost): void {
    const response = host.switchToHttp().getResponse<Response>();
    if (error instanceof HttpException) {
      const body = error.getResponse();
      response
        .status(error.getStatus())
        .json(
          typeof body === 'string'
            ? { statusCode: error.getStatus(), message: body }
            : body,
        );
      return;
    }
    response
      .status(503)
      .json({
        statusCode: 503,
        message:
          'Layanan perangkat display belum tersedia. Hubungi pengelola dan coba lagi setelah koneksi pulih.',
      });
  }
}
