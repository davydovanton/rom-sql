require 'dry-struct'

RSpec.describe 'Commands / Update', seeds: false do
  include_context 'users'

  subject(:users) { container.command(:users) }

  let(:update) { container.commands[:users][:update] }

  let(:relation) { container.relations.users }
  let(:piotr) { relation.by_name('Piotr').one }
  let(:peter) { { name: 'Peter' } }

  with_adapters do
    before do
      Test::User = Class.new(Dry::Struct) {
        attribute :id, Types::Strict::Int
        attribute :name, Types::Strict::String
      }

      conf.relation(:users) do
        def by_id(id)
          where(id: id).limit(1)
        end

        def by_name(name)
          where(name: name)
        end
      end

      conf.commands(:users) do
        define(:update)
      end

      conf.mappers do
        register :users, entity: -> tuples { tuples.map { |tuple| Test::User.new(tuple) } }
      end

      relation.insert(name: 'Piotr')
      relation.insert(name: 'Jane')
    end

    context '#transaction' do
      it 'update record if there was no errors' do
        result = users.update.transaction do
          users.update.by_id(piotr[:id]).call(peter)
        end

        expect(result.value).to eq([{ id: 1, name: 'Peter' }])
      end

      it 'updates nothing if error was raised' do
        users.update.transaction do
          users.update.by_id(piotr[:id]).call(peter)
          raise ROM::SQL::Rollback
        end

        expect(relation.first[:name]).to eql('Piotr')
      end
    end

    describe '#call' do
      it 'updates relation tuples' do
        result = users.try do
          users.update.by_id(piotr[:id]).call(peter)
        end

        expect(result.value.to_a).to match_array([{ id: 1, name: 'Peter' }])
      end

      it 're-raises database errors' do |example|
        pending 'why is it failing on travis?' if ENV['TRAVIS'] && mysql?(example) && !jruby?

        expect {
          users.update.by_id(piotr[:id]).call(name: nil)
        }.to raise_error(ROM::SQL::NotNullConstraintError, /name/i)
      end

      it 'materializes single result' do
        result = users.update.by_name('Piotr').call(name: 'Pete')
        expect(result).to eq([
          { id: 1, name: 'Pete' }
        ])
      end

      it 'materializes multiple results' do
        result = users.update.by_name(%w(Piotr Jane)).call(name: 'Josie')
        expect(result).to eq([
          { id: 1, name: 'Josie' },
          { id: 2, name: 'Josie' }
        ])
      end
    end
  end
end
