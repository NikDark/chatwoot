class AddVkChannel < ActiveRecord::Migration[7.1]
  def change
    create_table :channel_vk do |t|
      t.integer :account_id, null: false
      t.string :access_token, null: false
      t.string :group_id, null: false
      t.string :group_name, null: false
      t.string :confirmation_token
      t.integer :authorization_error_count, default: 0
      t.boolean :reauthorization_required, default: false
      t.timestamps
    end

    add_index :channel_vk, :group_id
    add_index :channel_vk, [:account_id, :group_id], unique: true
    add_foreign_key :channel_vk, :accounts, on_delete: :cascade
  end
end