class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string   :name, null: false
      t.json     :scopes, null: false, default: []
      t.string   :prefix, null: false
      t.string   :token_digest, null: false
      t.datetime :last_used_at

      t.timestamps
    end
    add_index :api_tokens, :prefix, unique: true
  end
end
