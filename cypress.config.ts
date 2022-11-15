import { defineConfig } from 'cypress'

export default defineConfig({
  e2e: {
    baseUrl: 'http://localhost:3333',
    setupNodeEvents() {
      // implement node event listeners here
    },
  },
})
