export function parseIntThrowing(x: string): number {
  const parsed = parseInt(x, 10)
  if (isNaN(parsed)) {
    throw new Error(`Cannot parse ${x} as a number`)
  }
  return parsed
}
