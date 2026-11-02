/// Read every page without a total-record cap. A short page ends the scan;
/// cancellation prevents another request after the search page is disposed.
Stream<List<T>> readSearchPages<T>({
  required Future<List<T>> Function(T? after, int pageSize) fetchPage,
  bool Function()? isActive,
  int pageSize = 400,
}) async* {
  if (pageSize <= 0) throw ArgumentError.value(pageSize, 'pageSize');
  T? after;
  while (isActive?.call() ?? true) {
    final page = await fetchPage(after, pageSize);
    if (!(isActive?.call() ?? true)) return;
    if (page.isEmpty) return;
    yield page;
    if (page.length < pageSize) return;
    after = page.last;
  }
}
