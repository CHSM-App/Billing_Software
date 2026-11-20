const {
  slugify, validateSlug, looksAutoDerived, RESERVED, MAX_TOKEN_LEN,
} = require('../../src/storeToken');

// uniqueStoreToken() needs a live table to check collisions against, so it is
// not covered here (this suite has no DB). These are the pure naming rules —
// the part that decides what a shop's public link actually reads as.

describe('slugify', () => {
  test('lowercases and hyphenates', () => {
    expect(slugify('Vengurla Tech')).toBe('vengurla-tech');
  });

  test('drops punctuation rather than encoding it', () => {
    expect(slugify('Vengurla Tech & Co.')).toBe('vengurla-tech-co');
    expect(slugify("Raj's Kitchen #1")).toBe('raj-s-kitchen-1');
  });

  test('folds accents to ASCII instead of losing the letter', () => {
    expect(slugify('Café Bombay')).toBe('cafe-bombay');
  });

  test('collapses runs and trims edges', () => {
    expect(slugify('  Big   Bazaar  ')).toBe('big-bazaar');
    expect(slugify('---Hotel---')).toBe('hotel');
  });

  test('never ends on a hyphen, even when the length cap cuts mid-word', () => {
    for (const name of [
      'The Extraordinarily Long Restaurant Name Limited',
      'A B C D E F G H I J K L M N O P Q R S T U V W X Y Z',
      'Sri Sri Sri Venkateswara Grand Family Restaurant',
    ]) {
      const s = slugify(name);
      expect(s).not.toMatch(/-$/);
      expect(s.length).toBeLessThanOrEqual(MAX_TOKEN_LEN);
    }
  });

  test('a name with no Latin characters yields an empty slug', () => {
    // Not a failure — uniqueStoreToken() falls back to a random token so the
    // business still gets a working link.
    expect(slugify('किराणा दुकान')).toBe('');
    expect(slugify('!!!')).toBe('');
    expect(slugify('')).toBe('');
    expect(slugify(null)).toBe('');
  });

  test('leaves room for the duplicate suffix inside the column width', () => {
    // store_token is NVARCHAR(32); the longest slug plus '-9999' must fit.
    const longest = slugify('W'.repeat(100));
    expect(longest.length + '-9999'.length).toBeLessThanOrEqual(MAX_TOKEN_LEN);
  });

  test('route names that a shop could be called are reserved', () => {
    // A shop named "Menu" must not be able to shadow /store/:token/menu.
    for (const word of ['menu', 'orders', 'send-otp', 'verify-otp']) {
      expect(RESERVED.has(word)).toBe(true);
    }
    expect(RESERVED.has(slugify('Menu'))).toBe(true);
  });
});

describe('validateSlug', () => {
  // Judges what an owner TYPED, so it rejects rather than silently rewrites —
  // slugify() cleans a name we generated, this one refuses bad input.

  test('accepts an ordinary link', () => {
    expect(validateSlug('coastal-kitchen')).toBeNull();
    expect(validateSlug('shop24')).toBeNull();
  });

  test.each([
    ['',                  'Enter a link'],
    ['   ',               'Enter a link'],
    ['ab',                'Link must be at least 3 characters'],
    ['a'.repeat(33),      'Link must be 32 characters or fewer'],
    ['Coastal',           'Use lowercase letters only'],
    ['coastal kitchen',   'Use only letters, numbers and hyphens'],
    ['coastal_kitchen',   'Use only letters, numbers and hyphens'],
    ['coastal/kitchen',   'Use only letters, numbers and hyphens'],
    ['-coastal',          'Link cannot start or end with a hyphen'],
    ['coastal-',          'Link cannot start or end with a hyphen'],
    ['coastal--kitchen',  'Link cannot contain two hyphens in a row'],
    ['menu',              'That link is reserved'],
  ])('rejects %p', (input, expected) => {
    expect(validateSlug(input)).toBe(expected);
  });

  test('rejects anything shaped like an auto-generated random token', () => {
    // 32 hex chars is what the fallback/legacy tokens look like; letting an
    // owner type one invites confusion with another shop's link.
    expect(validateSlug('0123456789abcdef0123456789abcdef'))
      .toBe('That link is not available');
  });

  test('every reserved word is rejected outright', () => {
    for (const word of RESERVED) {
      expect(validateSlug(word)).not.toBeNull();
    }
  });
});

describe('looksAutoDerived', () => {
  // This is the whole reason a rename does not trample a custom link, so the
  // custom cases matter more than the auto ones.

  test('links we generated read as auto', () => {
    expect(looksAutoDerived('vengurla-tech', 'Vengurla Tech')).toBe(true);
    expect(looksAutoDerived('vengurla-tech-2', 'Vengurla Tech')).toBe(true);
    expect(looksAutoDerived('vengurla-tech-17', 'Vengurla Tech')).toBe(true);
  });

  test('a random fallback token reads as auto — nobody chose it', () => {
    expect(looksAutoDerived('d3d31c726eb3a4cd876332bd2656e84e', 'Any Name'))
      .toBe(true);
    expect(looksAutoDerived(null, 'Any Name')).toBe(true);
  });

  test('a link the owner picked reads as custom, so a rename leaves it', () => {
    expect(looksAutoDerived('coastal-kitchen', 'Vengurla Tech')).toBe(false);
    // Shares the prefix but is not a suffix WE would have generated.
    expect(looksAutoDerived('vengurla-tech-shop', 'Vengurla Tech')).toBe(false);
  });

  test('an unslugifiable name never claims a custom link is auto', () => {
    // slugify('किराणा') is '', which must not turn into a match-everything rule.
    expect(looksAutoDerived('coastal-kitchen', 'किराणा दुकान')).toBe(false);
  });
});
