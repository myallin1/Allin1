module.exports = {
  root: true,
  env: {
    es2021: true,
    node: true,
  },
  parser: '@typescript-eslint/parser',
  parserOptions: {
    project: ['tsconfig.json'],
    sourceType: 'module',
  },
  plugins: ['@typescript-eslint'],
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended',
  ],
  ignorePatterns: [
    '/lib/**/*',
    '/node_modules/**/*',
  ],
  rules: {
    'quotes': 'off',
    'indent': 'off',
    'max-len': 'off',
    '@typescript-eslint/no-explicit-any': 'off',
  },
};
