class CreateProviderConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :provider_configs do |t|
      t.string  :provider, null: false
      t.string  :base_url
      t.text    :api_key
      t.string  :default_model
      t.boolean :enabled, null: false, default: false

      t.timestamps
    end
    add_index :provider_configs, :provider, unique: true
  end
end
