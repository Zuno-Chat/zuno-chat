bool isUiaCancel(Object error) =>
    error is Exception && '$error' == 'Exception: Request has been canceled';
